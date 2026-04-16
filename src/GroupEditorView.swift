import SwiftUI

struct GroupEditorView: View {
    let groupID: UUID
    @Binding var name: String
    @Binding var parsingEnabled: Bool
    @Binding var parsingScript: String
    
    var onSave: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Group Settings")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.link).font(.caption)
            }
            
            TextField("Group Name", text: $name)
            
            Toggle("Parsing script", isOn: $parsingEnabled)
                .font(.caption)
            
            if parsingEnabled {
                TextEditor(text: $parsingScript)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(name.isEmpty)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}