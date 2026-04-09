import SwiftUI

struct ConnectionEditorView: View {
    @Binding var selectedID: UUID?
    @Binding var name: String
    @Binding var command: String
    @Binding var groupID: UUID?
    @Binding var usePrefix: Bool
    @Binding var useSuffix: Bool
    @Binding var setTabName: Bool
    
    var groups: [ConnectionGroup]
    
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
            
            // Group Selector
            HStack {
                Text("Group:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $groupID) {
                    Text("Ungrouped").tag(Optional<UUID>.none)
                    Divider()
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)

            // Options: Prefix / Suffix / Tab Name
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    Toggle(isOn: $usePrefix) {
                        Text("Use Prefix").font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                    
                    Toggle(isOn: $useSuffix) {
                        Text("Use Suffix").font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                }
                
                Toggle(isOn: $setTabName) {
                    Text("Set Tab Name").font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
            }
            .padding(.top, 4)
            
            Spacer().frame(height: 10)

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