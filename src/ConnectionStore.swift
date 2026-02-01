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
    
    // --- Import / Export Helpers (Name-based) ---
    
    func getSnapshot() -> ExportData {
        // Map internal groups to export groups (UUID -> Name)
        let expGroups = groups.map { ExportGroup(name: $0.name, isExpanded: $0.isExpanded) }
        
        // Map internal connections to export connections (GroupID -> GroupName)
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
        var newGroups: [ConnectionGroup] = []
        var newConnections: [Connection] = []
        var groupMap: [String: UUID] = [:]
        
        // 1. Restore Groups (Ensure unique names for mapping)
        for g in data.groups {
            if groupMap[g.name] == nil {
                let newG = ConnectionGroup(name: g.name, isExpanded: g.isExpanded)
                newGroups.append(newG)
                groupMap[g.name] = newG.id
            }
        }
        
        // 2. Restore Connections (Link by Name)
        for c in data.connections {
            var gID: UUID? = nil
            if let gName = c.group {
                gID = groupMap[gName]
                // Note: If the JSON references a group name that isn't in the 'groups' list,
                // the connection will become Ungrouped (nil).
            }
            newConnections.append(Connection(groupID: gID, name: c.name, command: c.command))
        }
        
        // Replace Store State
        self.groups = newGroups
        self.connections = newConnections
        save()
    }
    
    // --- Persistence (Internal UUIDs) ---
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
            save()
        }
    }
}
