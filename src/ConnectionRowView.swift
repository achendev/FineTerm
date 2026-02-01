import SwiftUI
import UniformTypeIdentifiers

struct ConnectionRowView: View {
    let connection: Connection
    let isHighlighted: Bool
    let isEditing: Bool
    let hideCommand: Bool
    let searchText: String
    
    // Callbacks
    let onTap: () -> Void
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Interactive Row Area
                // REPLACEMENT: Using HStack + TapGesture instead of Button to allow Drag gestures to pass through
                HStack {
                    VStack(alignment: .leading) {
                        Text(connection.name)
                            .font(.headline)
                            .foregroundColor(isHighlighted ? .white : (isEditing ? .accentColor : .primary))
                        
                        if !hideCommand || !searchText.isEmpty {
                            Text(connection.command)
                                .font(.caption)
                                .foregroundColor(isHighlighted ? .white.opacity(0.8) : .gray)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle()) // Ensures the empty space is clickable/draggable
                .onTapGesture {
                    onTap()
                }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() }
                    else { NSCursor.pop() }
                }
                
                // Connect Button (Icon)
                Button(action: onConnect) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 16))
                        .foregroundColor(isHighlighted ? .white.opacity(0.9) : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Connect")
                .padding(.leading, 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? AppColors.activeHighlight : Color.clear)
                    .padding(.horizontal, 4)
            )
            // DRAG SOURCE: Attached to the entire container
            .onDrag {
                if UserDefaults.standard.bool(forKey: "debugMode") {
                    print("DEBUG: DRAG START - dragging '\(connection.name)' (ID: \(connection.id))")
                }
                return NSItemProvider(object: connection.id.uuidString as NSString)
            }
            
            Divider()
        }
        .id(connection.id)
    }
}
