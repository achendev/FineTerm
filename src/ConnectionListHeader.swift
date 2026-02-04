import SwiftUI

struct ConnectionListHeader: View {
    @ObservedObject var store: ConnectionStore
    
    // Bindings
    @Binding var searchText: String
    @Binding var showSettings: Bool
    
    // Import/Export Bindings
    @Binding var isImporting: Bool
    @Binding var isExporting: Bool
    @Binding var documentToExport: ConnectionsDocument?
    
    // Action Callbacks
    var onImportFromClipboard: () -> Void
    var onExportToClipboard: (Bool) -> Void
    
    // Group Creation State
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Text("Connections").font(.headline)
                Spacer()
                
                // Import/Export Menu
                Menu {
                    Button("Export All to File") {
                        documentToExport = ConnectionsDocument(exportData: store.getSnapshot(onlyExpanded: false))
                        isExporting = true
                    }
                    Button("Export Expanded to File") {
                        documentToExport = ConnectionsDocument(exportData: store.getSnapshot(onlyExpanded: true))
                        isExporting = true
                    }
                    Button("Export All to Clipboard") {
                        onExportToClipboard(false)
                    }
                    Button("Export Expanded to Clipboard") {
                        onExportToClipboard(true)
                    }
                    Divider()
                    Button("Import from File") {
                        isImporting = true
                    }
                    Button("Import from Clipboard") {
                        onImportFromClipboard()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Import/Export")
                .padding(.trailing, 8)

                Button(action: { showSettings = true }) {
                    Image(systemName: "gear").font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding([.top, .horizontal])
            .padding(.bottom, 8)
            
            // Search Bar
            TextField("Search profiles...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused(isSearchFocused)
                .padding(.horizontal)
            
            // Group Creation Bar
            groupCreationBar
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    var groupCreationBar: some View {
        Group {
            if isCreatingGroup {
                HStack {
                    TextField("Group Name", text: $newGroupName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { submitNewGroup() }
                    
                    Button(action: submitNewGroup) { Image(systemName: "checkmark") }
                        .buttonStyle(.borderless)
                    
                    Button(action: { isCreatingGroup = false; newGroupName = "" }) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 8)
            } else {
                HStack {
                    Button(action: { isCreatingGroup = true }) {
                        HStack(spacing: 4) { Image(systemName: "plus.folder"); Text("New Group") }
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    // Bulk Expand/Collapse Buttons
                    HStack(spacing: 12) {
                        Button(action: { store.expandAllGroups() }) {
                            Image(systemName: "chevron.down.square")
                                .help("Expand All Groups")
                        }
                        Button(action: { store.collapseAllGroups() }) {
                            Image(systemName: "chevron.up.square")
                                .help("Collapse All Groups")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal).padding(.top, 4).padding(.bottom, 8)
            }
        }
    }
    
    func submitNewGroup() {
        if !newGroupName.isEmpty {
            store.addGroup(name: newGroupName)
            newGroupName = ""
            isCreatingGroup = false
        }
    }
}
