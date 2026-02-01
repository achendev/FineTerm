import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct ConnectionListView: View {
    @StateObject var store = ConnectionStore()
    
    // Form Inputs
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newGroupID: UUID? = nil
    @State private var newUsePrefix = true
    @State private var newUseSuffix = true
    
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
    @AppStorage("smartFilter") private var smartFilter = true
    
    // MARK: - Navigation Helpers
    
    // Helper to get connections sorted by Last Used (Descending)
    func getSortedConnections(groupID: UUID?) -> [Connection] {
        let list = store.connections.filter { $0.groupID == groupID }
        return list.sorted {
            let d1 = $0.lastUsed ?? Date.distantPast
            let d2 = $1.lastUsed ?? Date.distantPast
            if d1 != d2 {
                return d1 > d2 // Most recently used first
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    
    var visibleConnectionsForNav: [Connection] {
        if !searchText.isEmpty {
            return performFilter(searchText)
        }
        var list: [Connection] = []
        for group in store.groups {
            if group.isExpanded {
                // Use sorted list for navigation consistency
                list.append(contentsOf: getSortedConnections(groupID: group.id))
            }
        }
        list.append(contentsOf: getSortedConnections(groupID: nil))
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
                connections: getSortedConnections(groupID: group.id), // USE SORTED
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
            let ungrouped = getSortedConnections(groupID: nil) // USE SORTED
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
    
    // MARK: - Filter Logic
    func performFilter(_ text: String) -> [Connection] {
        if smartFilter {
            let terms = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if terms.isEmpty { return [] }
            
            return store.connections.filter { conn in
                terms.allSatisfy { term in
                    conn.name.localizedCaseInsensitiveContains(term) ||
                    conn.command.localizedCaseInsensitiveContains(term)
                }
            }
            .sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
        } else {
            return store.connections.filter {
                $0.name.localizedCaseInsensitiveContains(text) ||
                $0.command.localizedCaseInsensitiveContains(text)
            }
            .sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
        }
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
            newGroupID = conn.groupID
            newUsePrefix = conn.usePrefix
            newUseSuffix = conn.useSuffix
            highlightedConnectionID = conn.id
        }
        lastClickTime = now
        lastClickedID = conn.id
    }
    
    func launchConnection(_ conn: Connection) {
        store.touch(id: conn.id) // UPDATE LAST USED
        
        // Build terminal name prefix if enabled
        let changeTerminalName = UserDefaults.standard.bool(forKey: "changeTerminalName")
        let terminalNamePrefix = changeTerminalName ? "printf '\\033]0;\(conn.name)\\007'; clear; " : ""
        
        // Get prefix/suffix from settings
        var prefix = conn.usePrefix ? (UserDefaults.standard.string(forKey: "commandPrefix") ?? "") : ""
        var suffix = conn.useSuffix ? (UserDefaults.standard.string(forKey: "commandSuffix") ?? "") : ""
        
        // Replace template variables in prefix and suffix
        prefix = prefix
            .replacingOccurrences(of: "$PROFILE_NAME", with: conn.name)
            .replacingOccurrences(of: "$PROFILE_COMMAND", with: conn.command)
        suffix = suffix
            .replacingOccurrences(of: "$PROFILE_NAME", with: conn.name)
            .replacingOccurrences(of: "$PROFILE_COMMAND", with: conn.command)
        
        let finalCommand = terminalNamePrefix + prefix + conn.command + suffix
        TerminalBridge.launch(command: finalCommand)
        searchText = ""
        highlightedConnectionID = nil
    }
    
    func saveSelected() {
        if let id = selectedConnectionID {
            store.update(id: id, name: newName, command: newCommand, groupID: newGroupID, usePrefix: newUsePrefix, useSuffix: newUseSuffix)
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
            store.add(name: newName, command: newCommand, groupID: newGroupID, usePrefix: newUsePrefix, useSuffix: newUseSuffix)
            resetForm()
        }
    }
    
    func resetForm() {
        newName = ""
        newCommand = ""
        newGroupID = nil
        newUsePrefix = true
        newUseSuffix = true
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
        
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isSearchFocused = true
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 1. GLOBAL SHORTCUT HANDLING WITHIN APP (Priority High)
            // Checked *before* "showSettings" guard to ensure we can exit settings/edit modes instantly
            
            let defaults = UserDefaults.standard
            let targetKeyChar = defaults.string(forKey: "globalShortcutKey") ?? "n"
            let targetModifierStr = defaults.string(forKey: "globalShortcutModifier") ?? "command"
            
            if let targetCode = KeyboardInterceptor.getKeyCode(for: targetKeyChar),
               event.keyCode == targetCode {
                
                let flags = event.modifierFlags
                var modifierMatch = false
                
                switch targetModifierStr {
                    case "command": 
                        modifierMatch = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
                    case "control": 
                        modifierMatch = flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option)
                    case "option":  
                        modifierMatch = flags.contains(.option) && !flags.contains(.command) && !flags.contains(.control)
                    default: 
                        modifierMatch = false
                }
                
                if modifierMatch {
                    // Check if second activation should switch to Terminal
                    let secondActivationToTerminal = UserDefaults.standard.bool(forKey: "secondActivationToTerminal")
                    
                    // If search is already focused, settings closed, no editing - switch to Terminal
                    if secondActivationToTerminal && self.isSearchFocused && !self.showSettings && self.selectedConnectionID == nil {
                        DispatchQueue.main.async {
                            // Activate Terminal.app
                            if let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) {
                                terminalApp.activate(options: [.activateIgnoringOtherApps])
                            } else {
                                // Terminal not running - launch it
                                if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                    NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                                }
                            }
                        }
                        return nil // Swallow event
                    }
                    
                    // ACTION: Reset state and focus search
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    
                    DispatchQueue.main.async {
                        self.showSettings = false        // Close settings if open
                        self.selectedConnectionID = nil  // Deselect current row (exit edit mode)
                        self.resetForm()                 // Clear form
                        
                        // Toggle focus state to force update
                        self.isSearchFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.isSearchFocused = true
                        }
                    }
                    return nil // Swallow event
                }
            }
            
            // 2. Navigation Handling (Only if not in Settings)
            guard !showSettings else { return event }

            let currentList = visibleConnectionsForNav
            
            switch event.keyCode {
            case 125: // Arrow Down
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let nextIdx = min(idx + 1, currentList.count - 1)
                    highlightedConnectionID = currentList[nextIdx].id
                    return nil
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
                    // Delay launch to ensure Enter key is fully released
                    // before Terminal becomes active. This prevents the first Enter 
                    // in Terminal from being ignored.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.launchConnection(conn)
                    }
                    return nil
                }
            default: break
            }
            return event
        }
    }
}
