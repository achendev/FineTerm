import SwiftUI

struct Connection: Identifiable, Codable {
    var id = UUID()
    var name: String
    var command: String
}

class ConnectionStore: ObservableObject {
    @Published var connections: [Connection] = []
    
    private let fileURL: URL
    
    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        fileURL = paths[0].appendingPathComponent("mt_connections.json")
        load()
    }
    
    func add(name: String, command: String) {
        connections.append(Connection(name: name, command: command))
        save()
    }
    
    func update(id: UUID, name: String, command: String) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].name = name
            connections[index].command = command
            save()
        }
    }
    
    func remove(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
        save()
    }
    
    func delete(id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(connections) {
            try? data.write(to: fileURL)
        }
    }
    
    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Connection].self, from: data) {
            connections = decoded
        }
    }
}

struct ConnectionListView: View {
    @StateObject var store = ConnectionStore()
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var showSettings = false
    
    // Search State
    @State private var searchText = ""
    
    // Keyboard Navigation State
    @State private var highlightedConnectionID: UUID? = nil
    
    // UI Settings
    @AppStorage("hideCommandInList") private var hideCommandInList = true
    
    // State to track if we are editing a connection
    @State private var selectedConnectionID: UUID? = nil
    
    // Double-click simulation state
    @State private var lastClickTime: Date = Date.distantPast
    @State private var lastClickedID: UUID? = nil
    
    // Computed property for filtering
    var filteredConnections: [Connection] {
        if searchText.isEmpty {
            return store.connections
        } else {
            return store.connections.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.command.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Area (Title + Search)
            VStack(spacing: 0) {
                // Top Row: Title + Settings
                HStack {
                    Text("Connections")
                        .font(.headline)
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                }
                .padding([.top, .horizontal])
                .padding(.bottom, 8)
                
                // Search Bar
                TextField("Search profiles...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    // Auto-select first item when searching
                    .onChange(of: searchText) { _ in
                        if let first = filteredConnections.first {
                            highlightedConnectionID = first.id
                        } else {
                            highlightedConnectionID = nil
                        }
                    }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle()) 
            .onTapGesture {
                // Clicking header background cancels edit
                if selectedConnectionID != nil {
                    resetForm()
                }
            }

            Divider()

            // List Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredConnections) { conn in
                            let isHighlighted = (highlightedConnectionID == conn.id)
                            let isEditing = (selectedConnectionID == conn.id)
                            
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    // --- INTERACTIVE ROW AREA ---
                                    Button(action: {
                                        let now = Date()
                                        if lastClickedID == conn.id && now.timeIntervalSince(lastClickTime) < 0.3 {
                                            // Double Click detected -> Connect
                                            launchConnection(conn)
                                        } else {
                                            // Single Click -> Edit Mode (Instant)
                                            selectedConnectionID = conn.id
                                            newName = conn.name
                                            newCommand = conn.command
                                            // Also update highlight to this row
                                            highlightedConnectionID = conn.id
                                        }
                                        
                                        // Update State
                                        lastClickTime = now
                                        lastClickedID = conn.id
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(conn.name)
                                                    .font(.headline)
                                                    .foregroundColor(isHighlighted ? .white : (isEditing ? .accentColor : .primary))
                                                
                                                if !hideCommandInList || !searchText.isEmpty {
                                                    Text(conn.command)
                                                        .font(.caption)
                                                        .foregroundColor(isHighlighted ? .white.opacity(0.8) : .gray)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                    
                                    // --- CONNECT BUTTON ---
                                    Button("Connect") {
                                        launchConnection(conn)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isHighlighted ? Color.white.opacity(0.2) : nil) // Slight tint change if highlighted
                                    .padding(.leading, 8)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isHighlighted ? Color.accentColor : Color.clear)
                                        .padding(.horizontal, 4)
                                )
                                .id(conn.id) // For ScrollViewReader
                                
                                Divider()
                            }
                        }
                        
                        if filteredConnections.isEmpty && !searchText.isEmpty {
                            Text("No matching profiles")
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .onTapGesture {
                    if selectedConnectionID != nil {
                        resetForm()
                    }
                }
                // Handle Auto-Scrolling when using arrows
                .onChange(of: highlightedConnectionID) { id in
                    if let id = id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer / Edit Form
            VStack(alignment: .leading) {
                HStack {
                    Text(selectedConnectionID == nil ? "New Connection" : "Edit Connection")
                        .font(.headline)
                    Spacer()
                    if selectedConnectionID != nil {
                        Button("Cancel") {
                            resetForm()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }

                TextField("Name (e.g. Prod DB)", text: $newName)
                TextField("Command (e.g. ssh user@1.2.3.4)", text: $newCommand)
                
                if let selectedID = selectedConnectionID {
                    HStack(spacing: 12) {
                        Button("Save") {
                            if !newName.isEmpty && !newCommand.isEmpty {
                                store.update(id: selectedID, name: newName, command: newCommand)
                                resetForm()
                            }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            // Initial selection
            if let first = store.connections.first {
                highlightedConnectionID = first.id
            }
            
            // KEYBOARD MONITOR
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Only process if no modal sheet is presented
                guard !showSettings else { return event }
                
                let currentList = filteredConnections
                
                switch event.keyCode {
                case 125: // Arrow Down
                    if let current = highlightedConnectionID,
                       let idx = currentList.firstIndex(where: { $0.id == current }) {
                        let nextIdx = min(idx + 1, currentList.count - 1)
                        highlightedConnectionID = currentList[nextIdx].id
                        return nil // Consume event
                    } else if !currentList.isEmpty {
                        highlightedConnectionID = currentList[0].id
                        return nil
                    }
                    
                case 126: // Arrow Up
                    if let current = highlightedConnectionID,
                       let idx = currentList.firstIndex(where: { $0.id == current }) {
                        let prevIdx = max(idx - 1, 0)
                        highlightedConnectionID = currentList[prevIdx].id
                        return nil // Consume event
                    } else if !currentList.isEmpty {
                        highlightedConnectionID = currentList[0].id
                        return nil
                    }
                    
                case 36: // Enter / Return
                    // If we have a highlight and we are NOT in the editing fields (simple check)
                    // Note: If user is typing in "New Name" field, we probably want Enter to do something else?
                    // For now, let's assume if search box is focused OR list is focused, Enter launches.
                    // If selectedConnectionID is NOT nil, user is editing, so maybe don't launch?
                    if selectedConnectionID == nil, let current = highlightedConnectionID,
                       let conn = currentList.first(where: { $0.id == current }) {
                        launchConnection(conn)
                        return nil // Consume event
                    }
                    
                default:
                    break
                }
                return event
            }
        }
    }
    
    private func launchConnection(_ conn: Connection) {
        let prefix = UserDefaults.standard.string(forKey: "commandPrefix") ?? ""
        let suffix = UserDefaults.standard.string(forKey: "commandSuffix") ?? ""
        let finalCommand = prefix + conn.command + suffix
        TerminalBridge.launch(command: finalCommand)
    }
    
    private func resetForm() {
        newName = ""
        newCommand = ""
        selectedConnectionID = nil
        lastClickedID = nil
        // Reset highlight to top of list if possible, or keep as is? 
        // Best UX: Keep selection or reset to top if filtering changed.
    }
}
