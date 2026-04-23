import SwiftUI
import Combine

class LibraryViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredItems: [LibraryItem] = []
    @Published var selectedItemID: UUID? = nil
    @Published var isDeepSearchEnabled = false
    @Published var isImageOnlyEnabled = false
    
    private var store: LibraryStore
    private var cancellables = Set<AnyCancellable>()
    
    init(store: LibraryStore) {
        self.store = store
        self.filteredItems = store.items
        if let first = store.items.first {
            self.selectedItemID = first.id
        }
        
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main) 
            .combineLatest(store.$items, $isDeepSearchEnabled, $isImageOnlyEnabled)
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { (text, items, deepSearch, imageOnly) -> [LibraryItem] in
                var baseItems = items
                if imageOnly {
                    baseItems = baseItems.filter { $0.type == .image }
                    return baseItems
                }
                
                let allBlobs = deepSearch ? store.getAllBlobs() : [:]
                
                return SearchService.smartFilter(baseItems, query: text) { item in
                    let searchContent = deepSearch ? (allBlobs[item.id] ?? item.content) : item.content
                    return "\(item.title) \(searchContent)"
                }
            }
            .receive(on: DispatchQueue.main)
            .sink {[weak self] items in
                guard let self = self else { return }
                self.filteredItems = items
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
    
    func getSelectedItem() -> LibraryItem? {
        return filteredItems.first(where: { $0.id == selectedItemID })
    }
}

private let rowDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm dd/MM/yyyy"
    return formatter
}()

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    var onClose: () -> Void
    
    @StateObject private var viewModel: LibraryViewModel
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = ClipboardKeyHandler()
    @StateObject private var flagsMonitor = FlagsMonitor()
    
    init(store: LibraryStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: LibraryViewModel(store: store))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search library...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .disabled(viewModel.isImageOnlyEnabled)
                        .opacity(viewModel.isImageOnlyEnabled ? 0.5 : 1.0)
                    Toggle(isOn: $viewModel.isImageOnlyEnabled) { Image(systemName: "photo").foregroundColor(viewModel.isImageOnlyEnabled ? .accentColor : .secondary) }
                    .toggleStyle(.button).buttonStyle(.borderless).help("Show Only Images")
                    .onChange(of: viewModel.isImageOnlyEnabled) { enabled in
                        if enabled { viewModel.searchText = "" } else { isSearchFocused = true }
                    }
                    Toggle(isOn: $viewModel.isDeepSearchEnabled) { Image(systemName: "square.stack.3d.forward.dottedline").foregroundColor(viewModel.isDeepSearchEnabled ? .accentColor : .secondary) }
                    .toggleStyle(.button).buttonStyle(.borderless).disabled(viewModel.isImageOnlyEnabled).help("Deep Search: Include full content")
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.filteredItems.isEmpty {
                            Text("No results found").foregroundColor(.secondary).padding(.top, 20)
                        } else {
                            ForEach(viewModel.filteredItems) { item in
                                LibraryRow(
                                    item: item,
                                    isHighlighted: item.id == viewModel.selectedItemID,
                                    isShiftDown: flagsMonitor.isShiftDown,
                                    action: { select(item) },
                                    onDelete: { delete(item) }
                                ).id(item.id)
                                Divider()
                            }
                        }
                    }
                }
                .onChange(of: viewModel.selectedItemID) { id in
                    if let id = id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
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
                guard let window = event.window, window.title == "Library" else { return false }
                
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
    
    func select(_ item: LibraryItem) { store.copyToClipboard(item: item); onClose() }
    func delete(_ item: LibraryItem) { store.delete(id: item.id) }
}

struct LibraryRow: View {
    let item: LibraryItem
    let isHighlighted: Bool
    let isShiftDown: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var maxLines = 2
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(isHighlighted ? .white : .primary)
                
                if item.type == .image, let data = item.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: 150)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                } else {
                    Text(item.content)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(maxLines > 0 ? maxLines : nil)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(isHighlighted ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.trailing, 20)
            
            if isShiftDown {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.caption).foregroundColor(isHighlighted ? .white : .gray)
                }
                .buttonStyle(.borderless).help("Delete item").padding(4)
            } else {
                Text(rowDateFormatter.string(from: item.timestamp))
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundColor(isHighlighted ? .white.opacity(0.6) : .secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background(isHighlighted ? AppColors.activeHighlight : (isHovering ? AppColors.activeHighlight.opacity(0.1) : Color.clear))
        .onTapGesture { action() }
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}