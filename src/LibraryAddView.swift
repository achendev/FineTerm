import SwiftUI
import AppKit

struct LibraryAddView: View {
    @ObservedObject var store: LibraryStore
    var onClose: () -> Void
    
    @State private var title: String = ""
    @State private var textContent: String = ""
    @State private var isImage: Bool = false
    @State private var imageContent: NSImage? = nil
    
    @FocusState private var isTitleFocused: Bool
    @StateObject private var keyHandler = ClipboardKeyHandler()
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Add to Library").font(.headline)
            
            TextField("Title / Description", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTitleFocused)
            
            if isImage, let img = imageContent {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            } else {
                TextEditor(text: $textContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 300)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }
            
            HStack {
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction) // Binds to Esc
                
                Spacer()
                
                Button("Save (↵)") {
                    save()
                }
                .keyboardShortcut(.defaultAction) // Gives the native blue default glow
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            loadClipboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
            
            // Bypass SwiftUI's flaky Enter key responder chain on text fields entirely
            keyHandler.start { event in
                // Prevent background view leaks from hijacking other windows
                guard let window = event.window, window.title == "Add to Library" else { return false }
                
                if event.keyCode == 36 || event.keyCode == 76 { // Return or Numpad Enter
                    
                    // 1. If holding Cmd or Ctrl, always save (useful when inside the TextEditor)
                    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                        save()
                        return true
                    }
                    
                    // 2. If focused exactly on the single-line Title field, plain Enter saves
                    if isTitleFocused {
                        save()
                        return true
                    }
                    
                    // If focused on the TextEditor, we return false so Enter just adds a newline
                }
                return false
            }
        }
        .onDisappear {
            keyHandler.stop()
        }
    }
    
    private func loadClipboard() {
        let pb = NSPasteboard.general
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            self.isImage = true
            self.imageContent = image
            self.title = "Image"
        } else if let string = pb.string(forType: .string) {
            self.isImage = false
            self.textContent = string
        }
    }
    
    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Manual validation instead of disabling the button
        guard !trimmedTitle.isEmpty else {
            NSSound.beep()
            return
        }
        
        if isImage, let img = imageContent {
            store.add(title: trimmedTitle, image: img)
        } else {
            store.add(title: trimmedTitle, content: textContent)
        }
        onClose()
    }
}