import SwiftUI
import Combine
import CryptoKit
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
    // Separate storage for large text blobs AND full images: [UUID: Base64String]
    // Modified on Main Thread for UI consistency, saved via copy-on-write to background.
    private var blobs: [UUID: String] = [:]
    
    private let fileURL: URL
    private let blobsURL: URL
    
    private var timer: Timer?
    private var lastChangeCount: Int
    
    // Serial queue for processing heavy data (images, truncation) off the main thread
    private let processingQueue = DispatchQueue(label: "com.fineterm.clipboard.processing", qos: .userInitiated)
    
    // Serial queue for saving to disk (lowest priority)
    private let saveQueue = DispatchQueue(label: "com.fineterm.clipboard.save", qos: .utility)
    
    // Key for storing the encryption key in UserDefaults
    private let keyStorageName = "FineTermClipboardKey"
    
    init() {
        let fileManager = FileManager.default
        
        // Target: ~/Library/Application Support/<BundleID>/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.FineTerm"
        let appDir = appSupport.appendingPathComponent(bundleID)
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        
        fileURL = appDir.appendingPathComponent("clipboard_history.enc")
        blobsURL = appDir.appendingPathComponent("clipboard_blobs.enc")
        
        lastChangeCount = NSPasteboard.general.changeCount
        
        load()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
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
            
            // Priority: Check for Image first, then Text
            // Offload heavy processing to background queue
            if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                processAndAdd(image: image)
            } else if let newString = pb.string(forType: .string) {
                if !newString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    processAndAdd(content: newString)
                }
            }
        }
    }
    
    // MARK: - Async Processing
    
    private func processAndAdd(image: NSImage) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let id = UUID()
            let now = Date()
            
            // Resize / Compress (Heavy)
            let thumbSize = NSSize(width: 300, height: 300)
            let thumbnail = self.resize(image: image, to: thumbSize)
            
            var thumbData = thumbnail.tiffRepresentation
            if let tiff = thumbData, let bitmap = NSBitmapImageRep(data: tiff) {
                if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                    thumbData = jpeg
                }
            }
            
            // Full Blob (Heavy)
            var fullBlob: String? = nil
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                fullBlob = pngData.base64EncodedString()
            }
            
            let sizeDesc = "Image \(Int(image.size.width))x\(Int(image.size.height))"
            let item = ClipboardItem(
                id: id,
                content: sizeDesc,
                timestamp: now,
                type: .image,
                thumbnailData: thumbData
            )
            
            DispatchQueue.main.async {
                self.insertItem(item, blob: fullBlob)
            }
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
                displayContent = self.truncate(string: content, limitBytes: fastLimitBytes)
                
                if content.utf8.count <= slowLimitBytes {
                    fullContent = content
                } else {
                    fullContent = self.truncate(string: content, limitBytes: slowLimitBytes)
                }
            }
            
            let item = ClipboardItem(content: displayContent, timestamp: Date())
            
            DispatchQueue.main.async {
                self.insertItem(item, blob: fullContent)
            }
        }
    }
    
    private func insertItem(_ item: ClipboardItem, blob: String?) {
        // De-duplication check
        if item.type == .text, let first = history.first, first.type == .text {
            if let newBlob = blob {
                if let existingBlob = blobs[first.id], existingBlob == newBlob { return }
            } else {
                if first.content == item.content { return }
            }
        }
        
        history.insert(item, at: 0)
        
        if let b = blob {
            blobs[item.id] = b
        }
        
        pruneHistory()
        save() // Trigger background save
    }
    
    private func resize(image: NSImage, to maxSize: NSSize) -> NSImage {
        if image.size.width == 0 || image.size.height == 0 { return image }
        let widthRatio = maxSize.width / image.size.width
        let heightRatio = maxSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio)
        let finalRatio = min(ratio, 1.0)
        
        let newSize = NSSize(width: image.size.width * finalRatio, height: image.size.height * finalRatio)
        let newImage = NSImage(size: newSize)
        
        // lockFocus is safe on background threads in macOS 10.12+
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Pruning Logic
    
    private func pruneHistory() {
        let globalLimit = UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardHistorySize)
        let effectiveGlobalLimit = globalLimit > 0 ? globalLimit : 100
        
        let imageLimit = UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardMaxImages)
        let effectiveImageLimit = imageLimit > 0 ? imageLimit : 50
        
        // 1. Enforce Image Limit
        let currentImages = history.filter { $0.type == .image }
        if currentImages.count > effectiveImageLimit {
            let imagesToRemove = currentImages.suffix(currentImages.count - effectiveImageLimit)
            let idsToRemove = Set(imagesToRemove.map { $0.id })
            
            history.removeAll { idsToRemove.contains($0.id) }
            for id in idsToRemove { blobs.removeValue(forKey: id) }
        }
        
        // 2. Enforce Global Limit
        if history.count > effectiveGlobalLimit {
            let removedItems = history.suffix(from: effectiveGlobalLimit)
            for removed in removedItems {
                blobs.removeValue(forKey: removed.id)
            }
            history = Array(history.prefix(effectiveGlobalLimit))
        }
    }
    
    private func truncate(string: String, limitBytes: Int) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        if data.count <= limitBytes { return string }
        
        let truncatedData = data.prefix(limitBytes)
        if let safeString = String(data: truncatedData, encoding: .utf8) {
            return safeString
        }
        
        for i in 1...3 {
            if limitBytes - i > 0 {
                let smaller = data.prefix(limitBytes - i)
                if let safeString = String(data: smaller, encoding: .utf8) {
                    return safeString
                }
            }
        }
        return String(string.prefix(limitBytes))
    }
    
    func delete(id: UUID) {
        history.removeAll { $0.id == id }
        blobs.removeValue(forKey: id)
        save()
    }
    
    func removeDuplicates() {
        let historySnapshot = self.history
        let blobsSnapshot = self.blobs
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var seenContent = Set<String>()
            var idsToRemove: Set<UUID> = []
            
            for item in historySnapshot {
                let identifier: String
                if item.type == .text {
                    identifier = blobsSnapshot[item.id] ?? item.content
                } else {
                    if let base64 = blobsSnapshot[item.id] {
                        identifier = base64
                    } else if let thumb = item.thumbnailData {
                        identifier = thumb.base64EncodedString()
                    } else {
                        identifier = UUID().uuidString
                    }
                }
                
                if seenContent.contains(identifier) {
                    idsToRemove.insert(item.id)
                } else {
                    seenContent.insert(identifier)
                }
            }
            
            if !idsToRemove.isEmpty {
                DispatchQueue.main.async {
                    self.history.removeAll { idsToRemove.contains($0.id) }
                    for id in idsToRemove {
                        self.blobs.removeValue(forKey: id)
                    }
                    self.save()
                }
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        if item.type == .image {
            if let base64 = blobs[item.id],
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        } else {
            let contentToPaste = blobs[item.id] ?? item.content
            pb.setString(contentToPaste, forType: .string)
        }
    }
    
    func clear() {
        history.removeAll()
        blobs.removeAll()
        save()
    }
    
    func getFullContent(for item: ClipboardItem) -> String {
        return blobs[item.id] ?? item.content
    }
    
    // MARK: - Statistics
    
    func getStats() -> ClipboardStats {
        let historySize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let blobsSize = (try? FileManager.default.attributesOfItem(atPath: blobsURL.path)[.size] as? Int64) ?? 0
        
        var imgCount = 0
        var txtBlobCount = 0
        var imgBytes: Int64 = 0
        var txtBlobBytes: Int64 = 0
        
        for item in history {
            if item.type == .image {
                imgCount += 1
                if let thumb = item.thumbnailData {
                    imgBytes += Int64(thumb.count)
                }
                if let blob = blobs[item.id] {
                    imgBytes += Int64(blob.utf8.count)
                }
            } else {
                if let blob = blobs[item.id] {
                    txtBlobCount += 1
                    txtBlobBytes += Int64(blob.utf8.count)
                }
            }
        }
        
        return ClipboardStats(
            totalItems: history.count,
            imageCount: imgCount,
            textBlobCount: txtBlobCount,
            historyDiskSizeBytes: historySize,
            blobsDiskSizeBytes: blobsSize,
            imageContentSizeBytes: imgBytes,
            textBlobContentSizeBytes: txtBlobBytes
        )
    }
    
    // MARK: - Encryption & Persistence
    
    private func getEncryptionKey() -> SymmetricKey {
        let defaults = UserDefaults.standard
        if let keyString = defaults.string(forKey: keyStorageName),
           let keyData = Data(base64Encoded: keyString) {
            return SymmetricKey(data: keyData)
        } else {
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            defaults.set(keyData.base64EncodedString(), forKey: keyStorageName)
            return key
        }
    }

    private func save() {
        // Snapshot data on main thread for thread safety
        let historySnapshot = self.history
        let blobsSnapshot = self.blobs
        
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.performSave(history: historySnapshot, blobs: blobsSnapshot)
        }
    }
    
    private func performSave(history: [ClipboardItem], blobs: [UUID: String]) {
        do {
            let key = getEncryptionKey()
            
            // Save History
            let historyData = try JSONEncoder().encode(history)
            let historyBox = try AES.GCM.seal(historyData, using: key)
            if let combined = historyBox.combined {
                try combined.write(to: fileURL)
            }
            
            // Save Blobs
            if !blobs.isEmpty {
                let blobsData = try JSONEncoder().encode(blobs)
                let blobsBox = try AES.GCM.seal(blobsData, using: key)
                if let combined = blobsBox.combined {
                    try combined.write(to: blobsURL)
                }
            } else {
                try? FileManager.default.removeItem(at: blobsURL)
            }
            
        } catch {
            print("Clipboard Save Error: \(error)")
        }
    }
    
    private func load() {
        let key = getEncryptionKey()
        let decoder = JSONDecoder()
        
        if let encryptedData = try? Data(contentsOf: fileURL) {
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                let decryptedData = try AES.GCM.open(sealedBox, using: key)
                self.history = try decoder.decode([ClipboardItem].self, from: decryptedData)
            } catch {
                print("Clipboard History Load Error: \(error)")
            }
        }
        
        if let encryptedBlobs = try? Data(contentsOf: blobsURL) {
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: encryptedBlobs)
                let decryptedData = try AES.GCM.open(sealedBox, using: key)
                self.blobs = try decoder.decode([UUID: String].self, from: decryptedData)
            } catch {
                print("Clipboard Blobs Load Error: \(error)")
            }
        }
    }
}