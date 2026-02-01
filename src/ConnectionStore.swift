import SwiftUI

class ConnectionStore: ObservableObject {
    @Published var groups: [ConnectionGroup] = []
    @Published var connections: [Connection] = []
    
    private let fileURL: URL
    
    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        fileURL = paths[0].appendingPathComponent("mt_connections.json")
        load()
    }
    
    // --- Connection Logic ---
    func add(name: String, command: String, groupID: UUID? = nil) {
        connections.append(Connection(groupID: groupID, name: name, command: command))
        save()
    }
    
    func update(id: UUID, name: String, command: String) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].name = name
            connections[index].command = command
            save()
        }
    }
    
    func moveConnection(_ connectionID: UUID, toGroup groupID: UUID?) {
        if let index = connections.firstIndex(where: { $0.id == connectionID }) {
            connections[index].groupID = groupID
            save()
        }
    }
    
    func delete(id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }
    
    // --- Group Logic ---
    func addGroup(name: String) {
        groups.append(ConnectionGroup(name: name))
        save()
    }
    
    func toggleGroupExpansion(_ id: UUID) {
        if let index = groups.firstIndex(where: { $0.id == id }) {
            groups[index].isExpanded.toggle()
            save()
        }
    }
    
    func deleteGroup(id: UUID) {
        // 1. Move connections in this group to Ungrouped (nil)
        for i in 0..<connections.count {
            if connections[i].groupID == id {
                connections[i].groupID = nil
            }
        }
        // 2. Remove group
        groups.removeAll { $0.id == id }
        save()
    }
    
    // --- Persistence ---
    func save() {
        let data = StoreData(groups: groups, connections: connections)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL)
        }
    }
    
    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        
        let decoder = JSONDecoder()
        
        // 1. Try decoding new format
        if let storeData = try? decoder.decode(StoreData.self, from: data) {
            self.groups = storeData.groups
            self.connections = storeData.connections
            return
        }
        
        // 2. Fallback: Try decoding old format (Array of Connections) and migrate
        if let oldConnections = try? decoder.decode([Connection].self, from: data) {
            self.connections = oldConnections
            self.groups = []
            save() // Save in new format immediately
        }
    }
}
