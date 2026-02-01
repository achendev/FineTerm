import SwiftUI
import UniformTypeIdentifiers

struct ConnectionListView: View {
    @StateObject var store = ConnectionStore()
    
    // Form Inputs
    @State private var newName = ""
    @State private var newCommand = ""
    
    // Group Creation
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var groupToDelete: GroupAlertItem? = nil
    
    @State private var showSettings = false
    
    // Import/Export State
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var documentToExport: ConnectionsDocument?
    
    // Search & Focus
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Interaction State
    @State private var highlightedConnectionID: UUID? = nil
    @State private var selectedConnectionID: UUID? = nil
    @State private var lastClickTime: Date = Date.distantPast
    @State private var lastClickedID: UUID? = nil
    
    @AppStorage("hideCommandInList") private var hideCommandInList = true
    
    // MARK: - Computed Properties
    
    var allFilteredConnections: [Connection] {
        if searchText.isEmpty {
            return store.connections
        } else {
            return store.connections.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.command.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var visibleConnectionsForNav: [Connection] {
        if !searchText.isEmpty { return allFilteredConnections }
        var list: [Connection] = []
        for group in store.groups {
            if group.isExpanded {
                list.append(contentsOf: store.connections.filter { $0.groupID == group.id })
            }
        }
        list.append(contentsOf: store.connections.filter { $0.groupID == nil })
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            mainListView
            Divider()
            footerView
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
        // Import Handler (Decodes User-Friendly JSON)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    if let data = try? Data(contentsOf: url),
                       let exportData = try? JSONDecoder().decode(ExportData.self, from: data) {
                        store.restore(from: exportData)
                    } else {
                        print("Import failed: JSON format mismatch (Expected ExportData format)")
                    }
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        // Export Handler
        .fileExporter(
            isPresented: $isExporting,
            document: documentToExport,
            contentType: .json,
            defaultFilename: "mt_connections_backup"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error.localizedDescription)")
            }
        }
        .onAppear(perform: setupOnAppear)
    }
    
    // MARK: - Subviews
    
    var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connections").font(.headline)
                Spacer()
                
                // Import/Export Menu
                Menu {
                    Button {
                        isImporting = true
                    } label: {
                        Text("Import JSON...")
                    }
                    
                    Button {
                        // Generate Snapshot for Export
                        documentToExport = ConnectionsDocument(exportData: store.getSnapshot())
                        isExporting = true
                    } label: {
                        Text("Export JSON...")
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
            
            TextField("Search profiles...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isSearchFocused)
                .padding(.horizontal)
                .onChange(of: searchText) { text in
                    if text.isEmpty { highlightedConnectionID = nil }
                    else if let first = allFilteredConnections.first { highlightedConnectionID = first.id }
                }
            
            groupCreationBar
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onTapGesture { if selectedConnectionID != nil { resetForm() } }
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
                }
                .padding(.horizontal).padding(.top, 4).padding(.bottom, 8)
            }
        }
    }
    
    var mainListView: some View {
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
            ForEach(allFilteredConnections) { conn in
                renderRow(conn)
            }
            if allFilteredConnections.isEmpty {
                Text("No matching profiles").foregroundColor(.gray).padding()
            }
        }
    }
    
    var groupedConnectionList: some View {
        Group {
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
            ungroupedSection
        }
    }
    
    var ungroupDropArea: some View {
        // DROP TARGET: Ungroup (Move to Root)
        Spacer(minLength: 50)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text, UTType.plainText], isTargeted: nil) { providers in
                if UserDefaults.standard.bool(forKey: "debugMode") {
                    print("DEBUG: DROP EVENT - Ungroup Area")
                }
                guard let item = providers.first else { return false }
                item.loadObject(ofClass: NSString.self) { (object, error) in
                    if let idStr = object as? String, let uuid = UUID(uuidString: idStr) {
                        DispatchQueue.main.async { store.moveConnection(uuid, toGroup: nil) }
                    }
                }
                return true
            }
    }
    
    var ungroupedSection: some View {
        let ungrouped = store.connections.filter { $0.groupID == nil }
        
        return Group {
            ForEach(ungrouped) { conn in
                renderRow(conn)
            }
        }
    }
    
    var footerView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(selectedConnectionID == nil ? "New Connection" : "Edit Connection")
                    .font(.headline)
                Spacer()
                if selectedConnectionID != nil {
                    Button("Cancel") { resetForm() }
                        .buttonStyle(.link).font(.caption)
                }
            }

            TextField("Name (e.g. Prod DB)", text: $newName)
            TextField("Command (e.g. ssh user@1.2.3.4)", text: $newCommand)
            
            if let selectedID = selectedConnectionID {
                HStack(spacing: 12) {
                    Button("Save") {
                        store.update(id: selectedID, name: newName, command: newCommand)
                        resetForm()
                    }
                    .disabled(newName.isEmpty || newCommand.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
                    Button("Delete") {
                        store.delete(id: selectedID)
                        resetForm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Button("Add Connection") {
                    if !newName.isEmpty && !newCommand.isEmpty {
                        store.add(name: newName, command: newCommand)
                        resetForm()
                    }
                }
                .disabled(newName.isEmpty || newCommand.isEmpty)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Logic Helpers
    
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
    
    func submitNewGroup() {
        if !newGroupName.isEmpty {
            store.addGroup(name: newGroupName)
            newGroupName = ""
            isCreatingGroup = false
        }
    }
    
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
    
    func resetForm() {
        newName = ""
        newCommand = ""
        selectedConnectionID = nil
        lastClickedID = nil
    }
    
    func setupOnAppear() {
        highlightedConnectionID = nil
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isSearchFocused = true
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !showSettings else { return event }
            let currentList = visibleConnectionsForNav
            
            switch event.keyCode {
            case 125: // Down
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let nextIdx = min(idx + 1, currentList.count - 1)
                    highlightedConnectionID = currentList[nextIdx].id
                    return nil
                } else if !currentList.isEmpty {
                    highlightedConnectionID = currentList[0].id
                    return nil
                }
            case 126: // Up
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
