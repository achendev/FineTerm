import SwiftUI
import UniformTypeIdentifiers

struct ConnectionListView: View {
    @StateObject var store = ConnectionStore()
    
    // Form Inputs
    @State private var newName = ""
    @State private var newCommand = ""
    
    // UI State
    @State private var showSettings = false
    @State private var groupToDelete: GroupAlertItem? = nil
    
    // Search & Focus
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Import/Export State
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var documentToExport: ConnectionsDocument?
    
    // Interaction State
    @State private var highlightedConnectionID: UUID? = nil
    @State private var selectedConnectionID: UUID? = nil
    @State private var lastClickTime: Date = Date.distantPast
    @State private var lastClickedID: UUID? = nil
    
    @AppStorage("hideCommandInList") private var hideCommandInList = true
    
    // MARK: - Navigation Helpers (CRITICAL: Required for Keyboard Support)
    // Returns the flat list of currently visible connections to support Up/Down arrow navigation
    var visibleConnectionsForNav: [Connection] {
        if !searchText.isEmpty {
            return store.connections.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.command.localizedCaseInsensitiveContains(searchText)
            }
        }
        // When not searching, visually ordered list (Groups -> Children -> Ungrouped)
        var list: [Connection] = []
        for group in store.groups {
            if group.isExpanded {
                list.append(contentsOf: store.connections.filter { $0.groupID == group.id })
            }
        }
        list.append(contentsOf: store.connections.filter { $0.groupID == nil })
        return list
    }
    
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
                isSearchFocused: $isSearchFocused
            )
            .onTapGesture { if selectedConnectionID != nil { resetForm() } }
            // CRITICAL: Auto-select first result when searching
            .onChange(of: searchText) { text in
                if !text.isEmpty {
                    let filtered = store.connections.filter {
                        $0.name.localizedCaseInsensitiveContains(text) ||
                        $0.command.localizedCaseInsensitiveContains(text)
                    }
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
    }
    
    // MARK: - List Rendering
    var mainScrollableList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
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
            let filtered = store.connections.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.command.localizedCaseInsensitiveContains(searchText)
            }
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
                connections: store.connections.filter { $0.groupID == group.id },
                highlightedID: highlightedConnectionID,
                selectedID: selectedConnectionID,
                hideCommand: hideCommandInList,
                searchText: searchText,
                onToggleExpand: { store.toggleGroupExpansion($0) },
                onDeleteGroup: { id in groupToDelete = GroupAlertItem(id: id) },
                onMoveConnection: { store.moveConnection($0, toGroup: $1) },
                onRowTap: handleRowTap,
                onRowConnect: launchConnection
            )
        }
    }
    
    var ungroupDropArea: some View {
        VStack(spacing: 0) {
            let ungrouped = store.connections.filter { $0.groupID == nil }
            ForEach(ungrouped) { conn in renderRow(conn) }
            
            // Drop target for moving to root
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

    // MARK: - Actions
    func handleRowTap(_ conn: Connection) {
        let now = Date()
        if lastClickedID == conn.id && now.timeIntervalSince(lastClickTime) < 0.3 {
            launchConnection(conn)
        } else {
            selectedConnectionID = conn.id
            newName = conn.name
            newCommand = conn.command
            highlightedConnectionID = conn.id
        }
        lastClickTime = now
        lastClickedID = conn.id
    }
    
    func launchConnection(_ conn: Connection) {
        let prefix = UserDefaults.standard.string(forKey: "commandPrefix") ?? ""
        let suffix = UserDefaults.standard.string(forKey: "commandSuffix") ?? ""
        let finalCommand = prefix + conn.command + suffix
        TerminalBridge.launch(command: finalCommand)
        searchText = ""
        highlightedConnectionID = nil
    }
    
    func saveSelected() {
        if let id = selectedConnectionID {
            store.update(id: id, name: newName, command: newCommand)
            resetForm()
        }
    }
    
    func deleteSelected() {
        if let id = selectedConnectionID {
            store.delete(id: id)
            resetForm()
        }
    }
    
    func addNew() {
        if !newName.isEmpty && !newCommand.isEmpty {
            store.add(name: newName, command: newCommand)
            resetForm()
        }
    }
    
    func resetForm() {
        newName = ""
        newCommand = ""
        selectedConnectionID = nil
        lastClickedID = nil
    }
    
    func handleImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url),
               let exportData = try? JSONDecoder().decode(ExportData.self, from: data) {
                store.restore(from: exportData)
            }
        }
    }
    
    func setupOnAppear() {
        highlightedConnectionID = nil
        
        // Ensure Search Field gets focus on active
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isSearchFocused = true
            }
        }
        
        // CRITICAL: Keyboard Navigation Implementation
        // Handles Up/Down/Enter global events when app is active
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !showSettings else { return event }
            let currentList = visibleConnectionsForNav
            
            switch event.keyCode {
            case 125: // Arrow Down
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let nextIdx = min(idx + 1, currentList.count - 1)
                    highlightedConnectionID = currentList[nextIdx].id
                    return nil // Stop propagation
                } else if !currentList.isEmpty {
                    highlightedConnectionID = currentList[0].id
                    return nil
                }
            case 126: // Arrow Up
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let prevIdx = max(idx - 1, 0)
                    highlightedConnectionID = currentList[prevIdx].id
                    return nil
                } else if !currentList.isEmpty {
                    highlightedConnectionID = currentList[0].id
                    return nil
                }
            case 36: // Enter
                if selectedConnectionID == nil, let current = highlightedConnectionID,
                   let conn = currentList.first(where: { $0.id == current }) {
                    launchConnection(conn)
                    return nil
                }
            default: break
            }
            return event
        }
    }
}
