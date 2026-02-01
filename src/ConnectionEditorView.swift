import SwiftUI

struct ConnectionEditorView: View {
    @Binding var selectedID: UUID?
    @Binding var name: String
    @Binding var command: String
    
    // Actions
    var onSave: () -> Void
    var onDelete: () -> Void
    var onAdd: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(selectedID == nil ? "New Connection" : "Edit Connection")
                    .font(.headline)
                Spacer()
                if selectedID != nil {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.link).font(.caption)
                }
            }

            TextField("Name (e.g. Prod DB)", text: $name)
            TextField("Command (e.g. ssh user@1.2.3.4)", text: $command)
            
            if selectedID != nil {
                HStack(spacing: 12) {
                    Button("Save", action: onSave)
                        .disabled(name.isEmpty || command.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    
                    Button("Delete", action: onDelete)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button("Add Connection", action: onAdd)
                    .disabled(name.isEmpty || command.isEmpty)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}
