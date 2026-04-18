import Cocoa

struct ClipboardProcessor {
    static func resize(image: NSImage, to maxSize: NSSize) -> NSImage {
        if image.size.width == 0 || image.size.height == 0 { return image }
        let widthRatio = maxSize.width / image.size.width
        let heightRatio = maxSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio)
        let finalRatio = min(ratio, 1.0)
        
        let newSize = NSSize(width: image.size.width * finalRatio, height: image.size.height * finalRatio)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    static func truncate(string: String, limitBytes: Int) -> String {
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
}