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

    static func save(history: [ClipboardItem], blobs: [UUID: String], fileURL: URL, blobsURL: URL) {
        do {
            let key = getEncryptionKey()
            let historyData = try JSONEncoder().encode(history)
            let historyBox = try AES.GCM.seal(historyData, using: key)
            if let combined = historyBox.combined {
                try combined.write(to: fileURL)
            }

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

    static func load(fileURL: URL, blobsURL: URL) -> (history: [ClipboardItem], blobs: [UUID: String]) {
        let key = getEncryptionKey()
        let decoder = JSONDecoder()
        var history: [ClipboardItem] = []
        var blobs: [UUID: String] = [:]

        if let encryptedData = try? Data(contentsOf: fileURL),
           let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
           let decryptedData = try? AES.GCM.open(sealedBox, using: key),
           let h = try? decoder.decode([ClipboardItem].self, from: decryptedData) {
            history = h
        }

        if let encryptedBlobs = try? Data(contentsOf: blobsURL),
           let sealedBox = try? AES.GCM.SealedBox(combined: encryptedBlobs),
           let decryptedData = try? AES.GCM.open(sealedBox, using: key),
           let b = try? decoder.decode([UUID: String].self, from: decryptedData) {
            blobs = b
        }

        return (history, blobs)
    }
}