import SwiftUI
import Combine
import CryptoKit

class ClipboardStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    
    private let fileURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    
    // Key for storing the encryption key in UserDefaults
    private let keyStorageName = "FineTermClipboardKey"
    
    init() {
        let fileManager = FileManager.default
        
        // Target: ~/Library/Application Support/<BundleID>/clipboard_history.enc
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.FineTerm"
        let appDir = appSupport.appendingPathComponent(bundleID)
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        
        fileURL = appDir.appendingPathComponent("clipboard_history.enc")
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Migrate old plaintext data if exists
        migrateLegacyData()
        
        load()
    }
    
    private func migrateLegacyData() {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldURL = docs.appendingPathComponent("clipboard_history.json")
        
        // If old file exists and new file doesn't
        if fileManager.fileExists(atPath: oldURL.path) && !fileManager.fileExists(atPath: fileURL.path) {
            print("Migrating legacy clipboard history...")
            if let data = try? Data(contentsOf: oldURL),
               let loaded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                self.history = loaded
                // Save immediately to new encrypted location
                save()
                // Remove old plaintext file
                try? fileManager.removeItem(at: oldURL)
            }
        }
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
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            
            if let newString = NSPasteboard.general.string(forType: .string) {
                if !newString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(content: newString)
                }
            }
        }
    }
    
    func add(content: String) {
        if let first = history.first, first.content == content {
            return
        }
        
        let item = ClipboardItem(content: content, timestamp: Date())
        history.insert(item, at: 0)
        
        let limit = UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardHistorySize)
        let effectiveLimit = limit > 0 ? limit : 100
        
        if history.count > effectiveLimit {
            history = Array(history.prefix(effectiveLimit))
        }
        
        save()
    }
    
    func delete(id: UUID) {
        history.removeAll { $0.id == id }
        save()
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.content, forType: .string)
    }
    
    func clear() {
        history.removeAll()
        save()
    }
    
    // MARK: - Encryption & Persistence
    
    private func getEncryptionKey() -> SymmetricKey {
        let defaults = UserDefaults.standard
        if let keyString = defaults.string(forKey: keyStorageName),
           let keyData = Data(base64Encoded: keyString) {
            return SymmetricKey(data: keyData)
        } else {
            // Generate new 256-bit key
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            defaults.set(keyData.base64EncodedString(), forKey: keyStorageName)
            return key
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(history)
            let key = getEncryptionKey()
            
            // Encrypt using AES-GCM
            let sealedBox = try AES.GCM.seal(data, using: key)
            if let combined = sealedBox.combined {
                try combined.write(to: fileURL)
            }
        } catch {
            print("Clipboard Save Error: \(error)")
        }
    }
    
    private func load() {
        guard let encryptedData = try? Data(contentsOf: fileURL) else { return }
        
        do {
            let key = getEncryptionKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            if let loaded = try? JSONDecoder().decode([ClipboardItem].self, from: decryptedData) {
                self.history = loaded
            }
        } catch {
            print("Clipboard Load Error (Decryption failed): \(error)")
        }
    }
}
