import SwiftUI
import UniformTypeIdentifiers

struct GroupSectionView: View {
    let group: ConnectionGroup
    let connections: [Connection]
    
    let highlightedID: UUID?
    let selectedID: UUID?
    let selectedGroupID: UUID?
    let hideCommand: Bool
    let searchText: String
    
    let isParsing: Bool
    
    let onToggleExpand: (UUID) -> Void
    let onDeleteGroup: (UUID, Bool) -> Void
    let onMoveConnection: (UUID, UUID?) -> Void
    let onRowTap: (Connection) -> Void
    let onRowConnect: (Connection) -> Void
    let onSelectGroup: (ConnectionGroup) -> Void
    let onRunScript: (UUID) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Group Header
            HStack(spacing: 0) {
                // Expand/Collapse Clickable Area
                HStack {
                    Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 15)
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { onToggleExpand(group.id) }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                
                // Select Group Area
                HStack {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(selectedGroupID == group.id ? .accentColor : .primary)
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { onSelectGroup(group) }
                
                // Actions Area
                HStack(spacing: 12) {
                    if let script = group.parsingScript, !script.isEmpty {
                        if isParsing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Button(action: { onRunScript(group.id) }) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedGroupID == group.id ? .accentColor : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Run Parsing Script")
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                    
                    Button(action: { 
                        // Detect Shift key for recursive delete
                        let isShift = NSEvent.modifierFlags.contains(.shift)
                        onDeleteGroup(group.id, isShift) 
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Group (Hold Shift to delete contents too)")
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .padding(.trailing, 10)
                .padding(.vertical, 6)
            }
            .background(selectedGroupID == group.id ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            // DROP TARGET: Add Connection to Group
            .onDrop(of: [UTType.text, UTType.plainText], isTargeted: nil) { providers in
                if UserDefaults.standard.bool(forKey: "debugMode") {
                    print("DEBUG: DROP EVENT - Group '\(group.name)' received items")
                }
                
                guard let item = providers.first else { return false }
                
                item.loadObject(ofClass: NSString.self) { (object, error) in
                    if let error = error {
                        print("DEBUG: Drop Load Error: \(error)")
                        return
                    }
                    
                    if let idStr = object as? String, let uuid = UUID(uuidString: idStr) {
                        if UserDefaults.standard.bool(forKey: "debugMode") {
                            print("DEBUG: Moving connection \(uuid) to group \(group.name)")
                        }
                        DispatchQueue.main.async {
                            onMoveConnection(uuid, group.id)
                        }
                    } else {
                        print("DEBUG: Could not parse dropped object as UUID string")
                    }
                }
                return true
            }

            // Group Items
            if group.isExpanded {
                ForEach(connections) { conn in
                    ConnectionRowView(
                        connection: conn,
                        isHighlighted: highlightedID == conn.id,
                        isEditing: selectedID == conn.id,
                        hideCommand: hideCommand,
                        searchText: searchText,
                        onTap: { onRowTap(conn) },
                        onConnect: { onRowConnect(conn) }
                    )
                    .padding(.leading, 16) // Indentation for tree view effect
                }
            }
        }
    }
}