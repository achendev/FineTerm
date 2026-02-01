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
        for i in 0..<connections.count {
            if connections[i].groupID == id {
                connections[i].groupID = nil
            }
        }
        groups.removeAll { $0.id == id }
        save()
    }
    
    // --- Import / Export Helpers ---
    
    func getSnapshot() -> ExportData {
        // Map groups (UUID -> Name), omit isExpanded
        let expGroups = groups.map { ExportGroup(name: $0.name) }
        
        // Map connections (GroupID -> GroupName)
        let expConnections = connections.map { conn -> ExportConnection in
            var groupName: String? = nil
            if let gID = conn.groupID, let g = groups.first(where: { $0.id == gID }) {
                groupName = g.name
            }
            return ExportConnection(name: conn.name, command: conn.command, group: groupName)
        }
        
        return ExportData(groups: expGroups, connections: expConnections)
    }
    
    func restore(from data: ExportData) {
        // MERGE STRATEGY: Add non-existing items, preserve existing ones.
        
        // 1. Index Existing Groups by Name
        var groupNameMap: [String: UUID] = [:]
        for group in self.groups {
            groupNameMap[group.name] = group.id
        }
        
        // 2. Merge Groups (Append if missing)
        for g in data.groups {
            if groupNameMap[g.name] == nil {
                let newG = ConnectionGroup(name: g.name, isExpanded: true)
                self.groups.append(newG)
                groupNameMap[g.name] = newG.id
            }
        }
        
        // 3. Merge Connections (Append if missing)
        for c in data.connections {
            // Resolve Group ID
            var gID: UUID? = nil
            if let gName = c.group {
                gID = groupNameMap[gName]
            }
            
            // Check for duplicates (Name + Command + Group must match to be considered duplicate)
            let exists = self.connections.contains { existing in
                return existing.name == c.name &&
                       existing.command == c.command &&
                       existing.groupID == gID
            }
            
            if !exists {
                self.connections.append(Connection(groupID: gID, name: c.name, command: c.command))
            }
        }
        
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
        
        if let storeData = try? decoder.decode(StoreData.self, from: data) {
            self.groups = storeData.groups
            self.connections = storeData.connections
            return
        }
        
        if let oldConnections = try? decoder.decode([Connection].self, from: data) {
            self.connections = oldConnections
            self.groups = []
            save()
        }
    }
}
