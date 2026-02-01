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
    
    // UI Settings
    @AppStorage("hideCommandInList") private var hideCommandInList = true
    
    // State to track if we are editing a connection
    @State private var selectedConnectionID: UUID? = nil
    
    // Double-click simulation state
    @State private var lastClickTime: Date = Date.distantPast
    @State private var lastClickedID: UUID? = nil
    
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
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredConnections) { conn in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                // --- INTERACTIVE ROW AREA ---
                                // Wrapped in a Plain Button to support "Click-Through" on inactive windows
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
                                    }
                                    
                                    // Update State
                                    lastClickTime = now
                                    lastClickedID = conn.id
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(conn.name)
                                                .font(.headline)
                                                .foregroundColor(selectedConnectionID == conn.id ? .accentColor : .primary)
                                            
                                            // Highlight match in command if searching
                                            if !hideCommandInList || !searchText.isEmpty {
                                                Text(conn.command)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle()) // Ensures the whole area is clickable within the button
                                }
                                .buttonStyle(.plain) // Removes standard button chrome
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
                                .padding(.leading, 8)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            
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
                // Clicking empty space in the ScrollView cancels edit
                if selectedConnectionID != nil {
                    resetForm()
                }
            }
            
            Divider()
            
            // Footer / Edit Form
            VStack(alignment: .leading) {
                HStack {
                    Text(selectedConnectionID == nil ? "New Connection" : "Edit Connection")
                        .font(.headline)
                    Spacer()
                    // Cancel button to exit edit mode easily
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
                    // Edit Mode: Save (Blue) and Delete (Red) buttons
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
                    // Add Mode
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
    }
}
