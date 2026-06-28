import Cocoa
import SwiftUI

// Logic Extension for ConnectionListView
extension ConnectionListView {
    
    // MARK: - Navigation Helpers
    
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
                list.append(contentsOf: getSortedConnections(groupID: group.id))
            }
        }
        list.append(contentsOf: getSortedConnections(groupID: nil))
        return list
    }
    
    // MARK: - Filter Logic
    func performFilter(_ text: String) -> [Connection] {
        if smartFilter {
            // DRY: Using Shared Search Service
            // We combine name and command into a single searchable string
            return SearchService.smartFilter(store.connections, query: text) { conn in
                return "\(conn.name) \(conn.command)"
            }
            .sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
        } else {
            // Legacy/Simple match
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
            selectedGroupID = nil
            newName = conn.name
            newCommand = conn.command
            newGroupID = conn.groupID
            newUsePrefix = conn.usePrefix
            newUseSuffix = conn.useSuffix
            newSetTabName = conn.setTabName
            highlightedConnectionID = conn.id
        }
        lastClickTime = now
        lastClickedID = conn.id
    }
    
    func handleGroupTap(_ group: ConnectionGroup) {
        let now = Date()
        selectedGroupID = group.id
        selectedConnectionID = nil
        highlightedConnectionID = nil
        
        editGroupName = group.name
        editGroupParsingScript = group.parsingScript ?? ""
        editGroupParsingEnabled = group.parsingScript != nil
        
        lastClickTime = now
        lastClickedID = group.id
    }
    
    func launchConnection(_ conn: Connection) {
        store.touch(id: conn.id) // UPDATE LAST USED
        
        let changeTerminalName = UserDefaults.standard.bool(forKey: AppConfig.Keys.changeTerminalName)
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        let isGhostty = target == "com.mitchellh.ghostty"
        let isIterm = target == "com.googlecode.iterm2"
        
        // Background terminal name setting
        var terminalNamePrefix = ""
        if changeTerminalName && conn.setTabName && !isGhostty {
            let template = UserDefaults.standard.string(forKey: AppConfig.Keys.terminalTabNameCommand) ?? "( ( sleep 2 ; printf '\\e]1;%s\\a' '$PROFILE_NAME' ) 2>/dev/null & ) 2>/dev/null ; clear ; "
            terminalNamePrefix = template.replacingOccurrences(of: "$PROFILE_NAME", with: conn.name)
                                         .replacingOccurrences(of: "$PROFILE_COMMAND", with: conn.command)
        }
        
        var prefix = conn.usePrefix ? (UserDefaults.standard.string(forKey: AppConfig.Keys.commandPrefix) ?? "") : ""
        var suffix = conn.useSuffix ? (UserDefaults.standard.string(forKey: AppConfig.Keys.commandSuffix) ?? "") : ""
        
        // Template replacement
        prefix = prefix
            .replacingOccurrences(of: "$PROFILE_NAME", with: conn.name)
            .replacingOccurrences(of: "$PROFILE_COMMAND", with: conn.command)
        suffix = suffix
            .replacingOccurrences(of: "$PROFILE_NAME", with: conn.name)
            .replacingOccurrences(of: "$PROFILE_COMMAND", with: conn.command)
        
        let finalCommand = terminalNamePrefix + prefix + conn.command + suffix
        
        if isGhostty {
            let tabName = (changeTerminalName && conn.setTabName) ? conn.name : nil
            GhosttyBridge.launch(command: finalCommand, tabName: tabName)
        } else if isIterm {
            let tabName = (changeTerminalName && conn.setTabName) ? conn.name : nil
            ItermBridge.launch(command: finalCommand, tabName: tabName)
        } else {
            TerminalBridge.launch(command: finalCommand)
        }
        
        searchText = ""
        highlightedConnectionID = nil
    }
    
    func saveSelected() {
        if let id = selectedConnectionID {
            // Validation: Do not save if fields are empty
            if newName.isEmpty || newCommand.isEmpty { return }
            
            store.update(id: id, name: newName, command: newCommand, groupID: newGroupID, usePrefix: newUsePrefix, useSuffix: newUseSuffix, setTabName: newSetTabName)
            resetForm()
        }
    }
    
    func saveSelectedGroup() {
        if let id = selectedGroupID {
            if editGroupName.isEmpty { return }
            let script = editGroupParsingEnabled ? editGroupParsingScript : nil
            store.updateGroup(id: id, name: editGroupName, parsingScript: script)
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
            store.add(name: newName, command: newCommand, groupID: newGroupID, usePrefix: newUsePrefix, useSuffix: newUseSuffix, setTabName: newSetTabName)
            resetForm()
        }
    }
    
    func resetForm() {
        newName = ""
        newCommand = ""
        newGroupID = nil
        newUsePrefix = true
        newUseSuffix = true
        newSetTabName = true
        selectedConnectionID = nil
        selectedGroupID = nil
        lastClickedID = nil
    }
    
    func updateAllParsedGroups() {
        let groupsToUpdate = store.groups.filter { ($0.parsingScript?.isEmpty == false) }
        
        for group in groupsToUpdate {
            self.parsingGroupIDs.insert(group.id)
            self.store.runParsingScript(for: group.id) { errorMsg in
                self.parsingGroupIDs.remove(group.id)
                if let errorMsg = errorMsg {
                    self.parsingErrorAlert = ParsingErrorAlert(message: "Group '\(group.name)': \(errorMsg)")
                }
            }
        }
    }
    
    // MARK: - Import / Export
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
    
    func importFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string),
              let data = string.data(using: .utf8) else {
            NSSound.beep()
            return
        }
        
        do {
            let exportData = try JSONDecoder().decode(ExportData.self, from: data)
            store.restore(from: exportData)
        } catch {
            print("Import Error: \(error)")
            NSSound.beep()
        }
    }
    
    func exportToClipboard(onlyExpanded: Bool) {
        let exportData = store.getSnapshot(onlyExpanded: onlyExpanded)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(exportData)
            if let string = String(data: data, encoding: .utf8) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(string, forType: .string)
            }
        } catch {
            print("Export Error: \(error)")
            NSSound.beep()
        }
    }
}