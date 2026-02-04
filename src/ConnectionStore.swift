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
    func add(name: String, command: String, groupID: UUID? = nil, usePrefix: Bool = true, useSuffix: Bool = true) {
        connections.append(Connection(groupID: groupID, name: name, command: command, usePrefix: usePrefix, useSuffix: useSuffix))
        save()
    }
    
    func update(id: UUID, name: String, command: String, groupID: UUID?, usePrefix: Bool, useSuffix: Bool) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].name = name
            connections[index].command = command
            connections[index].groupID = groupID
            connections[index].usePrefix = usePrefix
            connections[index].useSuffix = useSuffix
            save()
        }
    }
    
    // Update the lastUsed timestamp
    func touch(id: UUID) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].lastUsed = Date()
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
    
    func deleteGroupRecursive(id: UUID) {
        connections.removeAll { $0.groupID == id }
        groups.removeAll { $0.id == id }
        save()
    }
    
    // --- Import / Export Helpers ---
    
    func getSnapshot() -> ExportData {
        let expGroups = groups.map { ExportGroup(name: $0.name) }
        
        let expConnections = connections.map { conn -> ExportConnection in
            var groupName: String? = nil
            if let gID = conn.groupID, let g = groups.first(where: { $0.id == gID }) {
                groupName = g.name
            }
            return ExportConnection(
                name: conn.name,
                command: conn.command,
                group: groupName,
                usePrefix: conn.usePrefix,
                useSuffix: conn.useSuffix
            )
        }
        
        return ExportData(groups: expGroups, connections: expConnections)
    }
    
    func restore(from data: ExportData) {
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
        
        // 3. Merge Connections (Overwrite by Name)
        for c in data.connections {
            // Resolve Group ID
            var gID: UUID? = nil
            if let gName = c.group {
                gID = groupNameMap[gName]
            }
            
            if let index = self.connections.firstIndex(where: { $0.name == c.name }) {
                // Overwrite existing connection with matching name
                self.connections[index].command = c.command
                self.connections[index].groupID = gID
                self.connections[index].usePrefix = c.usePrefix ?? true
                self.connections[index].useSuffix = c.useSuffix ?? true
            } else {
                // Append new connection
                self.connections.append(Connection(
                    groupID: gID,
                    name: c.name,
                    command: c.command,
                    usePrefix: c.usePrefix ?? true,
                    useSuffix: c.useSuffix ?? true
                ))
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
        
        // Backward compatibility for really old version
        if let oldConnections = try? decoder.decode([Connection].self, from: data) {
            self.connections = oldConnections
            self.groups = []
            save()
        }
    }
}
