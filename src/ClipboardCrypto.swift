import Foundation
import CryptoKit

struct ClipboardCrypto {
    private static let keyStorageName = "FineTermClipboardKey"

    static func getEncryptionKey() -> SymmetricKey {
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

    static func saveHistory<T: Codable>(history: [T], fileURL: URL) {
        do {
            let key = getEncryptionKey()
            let historyData = try JSONEncoder().encode(history)
            let historyBox = try AES.GCM.seal(historyData, using: key)
            if let combined = historyBox.combined {
                try combined.write(to: fileURL)
            }
        } catch {
            print("Crypto Save History Error: \(error)")
        }
    }
    
    static func saveBlobs(blobs: [UUID: String], blobsURL: URL) {
        do {
            if blobs.isEmpty {
                try? FileManager.default.removeItem(at: blobsURL)
                return
            }
            let key = getEncryptionKey()
            let blobsData = try JSONEncoder().encode(blobs)
            let blobsBox = try AES.GCM.seal(blobsData, using: key)
            if let combined = blobsBox.combined {
                try combined.write(to: blobsURL)
            }
        } catch {
            print("Crypto Save Blobs Error: \(error)")
        }
    }

    static func loadHistory<T: Codable>(fileURL: URL, as type: T.Type) -> [T] {
        let key = getEncryptionKey()
        if let encryptedData = try? Data(contentsOf: fileURL),
           let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
           let decryptedData = try? AES.GCM.open(sealedBox, using: key),
           let history = try? JSONDecoder().decode([T].self, from: decryptedData) {
            return history
        }
        return []
    }
    
    static func loadBlobs(blobsURL: URL) -> [UUID: String] {
        let key = getEncryptionKey()
        if let encryptedBlobs = try? Data(contentsOf: blobsURL),
           let sealedBox = try? AES.GCM.SealedBox(combined: encryptedBlobs),
           let decryptedData = try? AES.GCM.open(sealedBox, using: key),
           let blobs = try? JSONDecoder().decode([UUID: String].self, from: decryptedData) {
            return blobs
        }
        return [:]
    }
}