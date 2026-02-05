import SwiftUI
import Combine

class ClipboardStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    
    private let fileURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    
    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        fileURL = paths[0].appendingPathComponent("clipboard_history.json")
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
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            
            if let newString = NSPasteboard.general.string(forType: .string) {
                // Avoid empty strings
                if !newString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(content: newString)
                }
            }
        }
    }
    
    func add(content: String) {
        // According to requirements: "brought back element just leave where it is and it's value also becoming new element"
        // This implies we don't deduplicate against the existing list, we just push to top.
        // However, standard clipboard managers usually avoid consecutive duplicates.
        if let first = history.first, first.content == content {
            return
        }
        
        let item = ClipboardItem(content: content, timestamp: Date())
        history.insert(item, at: 0)
        
        // Read limit from settings
        let limit = UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardHistorySize)
        let effectiveLimit = limit > 0 ? limit : 100
        
        if history.count > effectiveLimit {
            history = Array(history.prefix(effectiveLimit))
        }
        
        save()
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.content, forType: .string)
        // The timer will pick this up as a change and add it to history top as well
    }
    
    func clear() {
        history.removeAll()
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(history) {
            try? encoded.write(to: fileURL)
        }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let loaded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.history = loaded
        }
    }
}

