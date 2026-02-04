import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// Main View Structure
// Note: State properties are internal (not private) to allow extensions to access them.
struct ConnectionListView: View {
    @StateObject var store = ConnectionStore()
    
    // Form Inputs
    @State var newName = ""
    @State var newCommand = ""
    @State var newGroupID: UUID? = nil
    @State var newUsePrefix = true
    @State var newUseSuffix = true
    
    // Group Creation Inputs (Lifted from Header to allow Keyboard control)
    @State var isCreatingGroup = false
    @State var newGroupName = ""
    
    // UI State
    @State var showSettings = false
    @State var groupToDelete: GroupAlertItem? = nil
    
    // Search & Focus
    @State var searchText = ""
    @FocusState var isSearchFocused: Bool
    
    // Import/Export State
    @State var isImporting = false
    @State var isExporting = false
    @State var documentToExport: ConnectionsDocument?
    
    // Interaction State
    @State var highlightedConnectionID: UUID? = nil
    @State var selectedConnectionID: UUID? = nil
    @State var lastClickTime: Date = Date.distantPast
    @State var lastClickedID: UUID? = nil
    
    @AppStorage("hideCommandInList") var hideCommandInList = true
    @AppStorage("smartFilter") var smartFilter = true
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            ConnectionListHeader(
                store: store,
                searchText: $searchText,
                showSettings: $showSettings,
                isImporting: $isImporting,
                isExporting: $isExporting,
                documentToExport: $documentToExport,
                onImportFromClipboard: importFromClipboard,
                onExportToClipboard: exportToClipboard,
                isCreatingGroup: $isCreatingGroup,
                newGroupName: $newGroupName,
                isSearchFocused: $isSearchFocused
            )
            .onTapGesture { if selectedConnectionID != nil { resetForm() } }
            .onChange(of: searchText) { text in
                if !text.isEmpty {
                    let filtered = performFilter(text)
                    if let first = filtered.first {
                        highlightedConnectionID = first.id
                    } else {
                        highlightedConnectionID = nil
                    }
                } else {
                    highlightedConnectionID = nil
                }
            }

            Divider()
            
            mainScrollableList
            
            Divider()
            
            ConnectionEditorView(
                selectedID: $selectedConnectionID,
                name: $newName,
                command: $newCommand,
                groupID: $newGroupID,
                usePrefix: $newUsePrefix,
                useSuffix: $newUseSuffix,
                groups: store.groups,
                onSave: saveSelected,
                onDelete: deleteSelected,
                onAdd: addNew,
                onCancel: resetForm
            )
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert(item: $groupToDelete) { item in
            Alert(
                title: Text("Delete Group?"),
                message: Text("Connections will be moved to 'Ungrouped'."),
                primaryButton: .destructive(Text("Delete")) { store.deleteGroup(id: item.id) },
                secondaryButton: .cancel()
            )
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileExporter(isPresented: $isExporting, document: documentToExport, contentType: .json, defaultFilename: "mt_connections_backup") { _ in }
        .onAppear(perform: setupOnAppear)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FineTermOpenSettings"))) { _ in
            showSettings = true
        }
    }
    
    // MARK: - List Rendering
    var mainScrollableList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // OPTIMIZATION: Use LazyVStack for performance with large lists
                LazyVStack(spacing: 0, pinnedViews: []) { 
                    if !searchText.isEmpty {
                        searchResultList
                    } else {
                        groupedConnectionList
                        ungroupDropArea
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .onTapGesture { if selectedConnectionID != nil { resetForm() } }
            .onChange(of: highlightedConnectionID) { id in
                if let id = id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
    
    var searchResultList: some View {
        Group {
            let filtered = performFilter(searchText)
            ForEach(filtered) { conn in renderRow(conn) }
            if filtered.isEmpty {
                Text("No matching profiles").foregroundColor(.gray).padding()
            }
        }
    }
    
    var groupedConnectionList: some View {
        ForEach(store.groups) { group in
            GroupSectionView(
                group: group,
                connections: getSortedConnections(groupID: group.id), 
                highlightedID: highlightedConnectionID,
                selectedID: selectedConnectionID,
                hideCommand: hideCommandInList,
                searchText: searchText,
                onToggleExpand: { store.toggleGroupExpansion($0) },
                onDeleteGroup: { id, isRecursive in 
                    if isRecursive {
                        store.deleteGroupRecursive(id: id)
                    } else {
                        groupToDelete = GroupAlertItem(id: id) 
                    }
                },
                onMoveConnection: { store.moveConnection($0, toGroup: $1) },
                onRowTap: handleRowTap,
                onRowConnect: launchConnection
            )
        }
    }
    
    var ungroupDropArea: some View {
        VStack(spacing: 0) {
            let ungrouped = getSortedConnections(groupID: nil) 
            ForEach(ungrouped) { conn in renderRow(conn) }
            
            Spacer(minLength: 50)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.text, UTType.plainText], isTargeted: nil) { providers in
                    guard let item = providers.first else { return false }
                    item.loadObject(ofClass: NSString.self) { (object, error) in
                        if let idStr = object as? String, let uuid = UUID(uuidString: idStr) {
                            DispatchQueue.main.async { store.moveConnection(uuid, toGroup: nil) }
                        }
                    }
                    return true
                }
        }
    }

    func renderRow(_ conn: Connection) -> some View {
        ConnectionRowView(
            connection: conn,
            isHighlighted: highlightedConnectionID == conn.id,
            isEditing: selectedConnectionID == conn.id,
            hideCommand: hideCommandInList,
            searchText: searchText,
            onTap: { handleRowTap(conn) },
            onConnect: { launchConnection(conn) }
        )
    }
}

