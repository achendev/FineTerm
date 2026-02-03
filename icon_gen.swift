import Cocoa

let size: CGFloat = 1024
// Adjusted padding to 100 (matches standard 824x824 icon grid size)
// Previous 120 was too small compared to Terminal.app
let padding: CGFloat = 100
// Adjusted corner radius to 185 (standard curvature for 824px size)
// Previous 225 was too round for the smaller inset
let cornerRadius: CGFloat = 185

let canvasRect = NSRect(x: 0, y: 0, width: size, height: size)
let iconRect = canvasRect.insetBy(dx: padding, dy: padding)

// 1. Create Image Context
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// 2. Clear Background (Transparency)
NSColor.clear.set()
NSBezierPath(rect: canvasRect).fill()

// 3. Load and Draw the Source Image with a Mask
let sourcePath = "FineTerm.png"
if let sourceImage = NSImage(contentsOfFile: sourcePath) {
    let path = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    
    sourceImage.draw(in: iconRect, from: NSRect(origin: .zero, size: sourceImage.size), operation: .sourceOver, fraction: 1.0)
} else {
    print("Error: Could not load \(sourcePath)")
}

img.unlockFocus()

// 4. Save as PNG
if let tiff = img.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "icon_1024.png"))
}

