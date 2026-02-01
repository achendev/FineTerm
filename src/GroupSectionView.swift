import SwiftUI
import UniformTypeIdentifiers

struct GroupSectionView: View {
    let group: ConnectionGroup
    let connections: [Connection]
    
    // Dependencies needed for row rendering
    let highlightedID: UUID?
    let selectedID: UUID?
    let hideCommand: Bool
    let searchText: String
    
    // Callbacks
    let onToggleExpand: (UUID) -> Void
    let onDeleteGroup: (UUID) -> Void
    let onMoveConnection: (UUID, UUID?) -> Void
    let onRowTap: (Connection) -> Void
    let onRowConnect: (Connection) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Group Header
            HStack {
                Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 15)
                
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { onDeleteGroup(group.id) }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.gray.opacity(0.1))
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand(group.id)
            }
            // DROP TARGET: Add Connection to Group
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                guard let item = providers.first else { return false }
                
                item.loadObject(ofClass: NSString.self) { (object, error) in
                    if let idStr = object as? String, let uuid = UUID(uuidString: idStr) {
                        DispatchQueue.main.async {
                            onMoveConnection(uuid, group.id)
                        }
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
                }
            }
        }
    }
}
