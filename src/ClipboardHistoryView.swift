import SwiftUI
import Combine

class ClipboardViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredItems: [ClipboardItem] = []
    @Published var selectedItemID: UUID? = nil
    
    // Deep Search State
    @Published var isDeepSearchEnabled = false
    
    // Image Filter State
    @Published var isImageOnlyEnabled = false
    
    private var store: ClipboardStore
    private var cancellables = Set<AnyCancellable>()
    
    init(store: ClipboardStore) {
        self.store = store
        
        // 1. Synchronous Init
        self.filteredItems = store.history
        if let first = store.history.first {
            self.selectedItemID = first.id
        }
        
        // 2. Setup Pipeline
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main) 
            .combineLatest(store.$history, $isDeepSearchEnabled, $isImageOnlyEnabled)
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { (text, history, deepSearch, imageOnly) -> [ClipboardItem] in
                var baseItems = history
                
                // Image Only Filter
                if imageOnly {
                    baseItems = baseItems.filter { $0.type == .image }
                    // When image filter is on, text search is ignored/blocked
                    return baseItems
                }
                
                let allBlobs = deepSearch ? store.getAllBlobs() : [:]
                
                // Normal Text Search
                return SearchService.smartFilter(baseItems, query: text) { item in
                    if deepSearch {
                        return allBlobs[item.id] ?? item.content
                    } else {
                        return item.content
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                self.filteredItems = items
                
                // Maintain selection or select first
                if let first = items.first, self.selectedItemID == nil || !items.contains(where: { $0.id == self.selectedItemID }) {
                    self.selectedItemID = first.id
                }
            }
            .store(in: &cancellables)
    }
    
    func moveSelection(_ direction: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let newIndex = max(0, min(filteredItems.count - 1, currentIndex + direction))
        selectedItemID = filteredItems[newIndex].id
    }
    
    func getSelectedItem() -> ClipboardItem? {
        return filteredItems.first(where: { $0.id == selectedItemID })
    }
}

class FlagsMonitor: ObservableObject {
    @Published var isShiftDown = false
    private var monitor: Any?
    
    init() { self.isShiftDown = NSEvent.modifierFlags.contains(.shift) }
    
    func start() {
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async { self?.isShiftDown = event.modifierFlags.contains(.shift) }
            return event
        }
    }
    
    func stop() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        self.monitor = nil
    }
    deinit { stop() }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    var onClose: () -> Void
    
    @StateObject private var viewModel: ClipboardViewModel
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = ClipboardKeyHandler()
    @StateObject private var flagsMonitor = FlagsMonitor()
    
    init(store: ClipboardStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ClipboardViewModel(store: store))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar Area
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search clipboard...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .disabled(viewModel.isImageOnlyEnabled)
                        .opacity(viewModel.isImageOnlyEnabled ? 0.5 : 1.0)
                    
                    // Image Filter Button
                    Toggle(isOn: $viewModel.isImageOnlyEnabled) {
                        Image(systemName: "photo")
                            .foregroundColor(viewModel.isImageOnlyEnabled ? .accentColor : .secondary)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Show Only Images (Blocks Search)")
                    .onChange(of: viewModel.isImageOnlyEnabled) { enabled in
                        if enabled {
                            viewModel.searchText = "" // Clear search when switching to images
                        } else {
                            isSearchFocused = true // Refocus when disabling
                        }
                    }

                    // Deep Search Toggle
                    Toggle(isOn: $viewModel.isDeepSearchEnabled) {
                        Image(systemName: "square.stack.3d.forward.dottedline")
                            .foregroundColor(viewModel.isDeepSearchEnabled ? .accentColor : .secondary)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isImageOnlyEnabled) // Disable deep search for images
                    .help("Deep Search: Include full content of large items")
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
            }
            
            // Results List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.filteredItems.isEmpty {
                            Text("No results found")
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
                        } else {
                            ForEach(viewModel.filteredItems) { item in
                                ClipboardRow(
                                    item: item,
                                    isHighlighted: item.id == viewModel.selectedItemID,
                                    isShiftDown: flagsMonitor.isShiftDown,
                                    action: { select(item) },
                                    onDelete: { delete(item) }
                                )
                                .id(item.id)
                                Divider()
                            }
                        }
                    }
                }
                .onChange(of: viewModel.selectedItemID) { id in
                    if let id = id {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isSearchFocused = true }
            flagsMonitor.start()
            keyHandler.start { event in
                // Prevent background view leaks from hijacking other windows
                guard let window = event.window, window.title == "Clipboard History" else { return false }
                
                switch event.keyCode {
                case 126: viewModel.moveSelection(-1); return true
                case 125: viewModel.moveSelection(1); return true
                case 36:
                    if let item = viewModel.getSelectedItem() {
                        let shiftEnterEnabled = UserDefaults.standard.bool(forKey: AppConfig.Keys.clipboardShiftEnterToEditor)
                        if shiftEnterEnabled && event.modifierFlags.contains(.shift) {
                            TextEditorBridge.shared.open(content: store.getFullContent(for: item))
                            onClose()
                        } else {
                            select(item)
                        }
                    }
                    return true
                default: return false
                }
            }
        }
        .onDisappear {
            keyHandler.stop()
            flagsMonitor.stop()
        }
    }
    
    func select(_ item: ClipboardItem) {
        store.copyToClipboard(item: item)
        onClose()
    }
    
    func delete(_ item: ClipboardItem) {
        store.delete(id: item.id)
    }
}

class ClipboardKeyHandler: ObservableObject {
    private var monitor: Any?
    func start(onKeyDown: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if onKeyDown(event) { return nil }
            return event
        }
    }
    func stop() { if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
}

private let rowDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm dd/MM/yyyy"
    return formatter
}()

struct ClipboardRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool
    let isShiftDown: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var maxLines = 2
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            // Content Layout
            if item.type == .image, let data = item.thumbnailData, let nsImage = NSImage(data: data) {
                // Image Mode: Full Width Preview, No Text Info
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Restrict max height reasonably (e.g. 200px), but allow it to shrink
                    // This prevents empty space if the image is wide and short
                    .frame(maxHeight: 200)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            } else {
                // Text Mode
                HStack(alignment: .top, spacing: 10) {
                    Text(item.content)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(maxLines > 0 ? maxLines : nil)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(isHighlighted ? .white : .primary)
                }
                .padding(.trailing, 20)
            }
            
            // Timestamp / Delete Button
            if isShiftDown {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(isHighlighted ? .white : .gray)
                }
                .buttonStyle(.borderless)
                .help("Delete item")
                .padding(4)
            } else {
                Text(rowDateFormatter.string(from: item.timestamp))
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundColor(isHighlighted ? .white.opacity(0.6) : .secondary.opacity(0.6))
                    // When showing image, add shadow and adjust padding to overlay top-right corner
                    .shadow(color: item.type == .image ? Color.black.opacity(0.5) : Color.clear, radius: 1, x: 0, y: 0)
                    .padding(.top, item.type == .image ? 4 : -7.2)
                    .padding(.trailing, item.type == .image ? 4 : -7.2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background(
            isHighlighted ? AppColors.activeHighlight : (isHovering ? AppColors.activeHighlight.opacity(0.1) : Color.clear)
        )
        .onTapGesture { action() }
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}