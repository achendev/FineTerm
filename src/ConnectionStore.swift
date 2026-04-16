import SwiftUI

struct ParsedConnection: Codable {
    let name: String
    let command: String
}

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
    func add(name: String, command: String, groupID: UUID? = nil, usePrefix: Bool = true, useSuffix: Bool = true, setTabName: Bool = true) {
        connections.append(Connection(groupID: groupID, name: name, command: command, usePrefix: usePrefix, useSuffix: useSuffix, setTabName: setTabName, isParsed: false))
        save()
    }
    
    func update(id: UUID, name: String, command: String, groupID: UUID?, usePrefix: Bool, useSuffix: Bool, setTabName: Bool) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].name = name
            connections[index].command = command
            connections[index].groupID = groupID
            connections[index].usePrefix = usePrefix
            connections[index].useSuffix = useSuffix
            connections[index].setTabName = setTabName
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
    
    func updateGroup(id: UUID, name: String, parsingScript: String?) {
        if let index = groups.firstIndex(where: { $0.id == id }) {
            groups[index].name = name
            groups[index].parsingScript = parsingScript
            save()
        }
    }
    
    func toggleGroupExpansion(_ id: UUID) {
        if let index = groups.firstIndex(where: { $0.id == id }) {
            groups[index].isExpanded.toggle()
            save()
        }
    }
    
    func expandAllGroups() {
        for i in 0..<groups.count { groups[i].isExpanded = true }
        save()
    }
    
    func collapseAllGroups() {
        for i in 0..<groups.count { groups[i].isExpanded = false }
        save()
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
    
    // --- Parsing Logic ---
    func runParsingScript(for groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let script = group.parsingScript, !script.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", script]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if task.terminationStatus == 0 {
                    let decoder = JSONDecoder()
                    if let parsedList = try? decoder.decode([ParsedConnection].self, from: data) {
                        DispatchQueue.main.async {
                            self.updateParsedConnections(for: groupID, groupName: group.name, parsed: parsedList)
                        }
                    } else {
                        print("Failed to decode JSON from parsing script output.")
                    }
                } else {
                    let errData = (task.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    print("Script failed with status \(task.terminationStatus). Err: \(String(data: errData, encoding: .utf8) ?? "")")
                }
            } catch {
                print("Failed to run script: \(error)")
            }
        }
    }
    
    private func updateParsedConnections(for groupID: UUID, groupName: String, parsed: [ParsedConnection]) {
        // Remove existing parsed
        connections.removeAll { $0.groupID == groupID && ($0.isParsed == true) }
        
        // Add new
        let newConns = parsed.map { p in
            Connection(
                groupID: groupID,
                name: "\(groupName)-\(p.name)",
                command: p.command,
                usePrefix: true,
                useSuffix: true,
                setTabName: true,
                lastUsed: nil,
                isParsed: true
            )
        }
        
        connections.append(contentsOf: newConns)
        save()
    }
    
    // --- Import / Export Helpers ---
    
    func getSnapshot(onlyExpanded: Bool = false) -> ExportData {
        // Filter groups if necessary
        let groupsToExport = onlyExpanded ? groups.filter { $0.isExpanded } : groups
        let expGroups = groupsToExport.map { ExportGroup(name: $0.name, parsingScript: $0.parsingScript) }
        
        let expConnections = connections.compactMap { conn -> ExportConnection? in
            var groupName: String? = nil
            
            if let gID = conn.groupID {
                // It belongs to a group
                if let group = groups.first(where: { $0.id == gID }) {
                    // Check if we should skip this connection because its group is collapsed
                    if onlyExpanded && !group.isExpanded {
                        return nil
                    }
                    groupName = group.name
                } else {
                    // Group ID not found (orphan), treat as ungrouped
                    if onlyExpanded { return nil }
                }
            } else {
                // Ungrouped connection
                if onlyExpanded { return nil }
            }
            
            return ExportConnection(
                name: conn.name,
                command: conn.command,
                group: groupName,
                usePrefix: conn.usePrefix,
                useSuffix: conn.useSuffix,
                setTabName: conn.setTabName,
                isParsed: conn.isParsed
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
                let newG = ConnectionGroup(name: g.name, isExpanded: true, parsingScript: g.parsingScript)
                self.groups.append(newG)
                groupNameMap[g.name] = newG.id
            } else if let existingId = groupNameMap[g.name], let gIdx = self.groups.firstIndex(where: { $0.id == existingId }) {
                if g.parsingScript != nil {
                    self.groups[gIdx].parsingScript = g.parsingScript
                }
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
                self.connections[index].setTabName = c.setTabName ?? true
                self.connections[index].isParsed = c.isParsed ?? false
            } else {
                // Append new connection
                self.connections.append(Connection(
                    groupID: gID,
                    name: c.name,
                    command: c.command,
                    usePrefix: c.usePrefix ?? true,
                    useSuffix: c.useSuffix ?? true,
                    setTabName: c.setTabName ?? true,
                    isParsed: c.isParsed ?? false
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