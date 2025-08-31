import SwiftUI
import AppKit

// NOTE: ColorOption, ProjectSnapshot, and HistoryManager were moved to their own files.
// NOTE: Large subviews and computed sections moved into extensions (separate files).
// NEW: Color option enum

struct SelectionsView: View {
    @EnvironmentObject var model: AppModel
    @State var autoSendToEnd = true
    @State var colorPanelObserver: NSObjectProtocol?
    @State var borderWidth: Double = 0.0
    // Add this line with your other @State variables (around line 85)
    @State var undoRedoKeyMonitor: Any?
    // NEW: History manager
    @StateObject var historyManager = HistoryManager()
    
    // NEW: System appearance toggle - ADD THESE LINES
    @AppStorage("selectedAppearance") var selectedAppearance: String = "light"
    @Environment(\.colorScheme) var systemColorScheme
    
    // ... rest of your existing properties
    
    // UI state
    @State var showDisabled = true
    @State var draggingID: UUID? = nil
    @State var columns: Int = 5
    @State var disabledOverlayOpacity: Double = 0.5
    @State var showResetConfirm = false
    
    // NEW: Background color for when zoom to fill is disabled
    @State var backgroundColor = Color.black // Changed default to black

    // Helper to sync backgroundColor to global project color
    private func syncBackgroundColorToProject() {
        let ns = NSColor(backgroundColor)
        let colorData = ColorData(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            opacity: 1
        )
        if model.project.aspect == .story9x16 {
            model.project.reelBorderColor = colorData
        } else {
            model.project.carouselBorderColor = colorData
        }
    }
    @State var selectedColorOption: ColorOption = .black // Track which option is selected
    
    // SIMPLIFIED: Direct reposition sheet state
    @State var repositionItem: ProjectImage? = nil
    
    // NEW: Full image view state - changed to Bool + item tracking
    @State var showFullImageView = false
    @State var fullViewItem: ProjectImage? = nil

    // Capture the "original order after coming from Folders"
    @State var originalOrderIDs: [UUID] = []
    @State var haveCapturedOriginal = false
    
    // NEW: Shift key state and hover tracking for repositioning
    @State var isShiftPressed = false
    @State var hoveredItemID: UUID? = nil
    @State var shiftKeyMonitor: Any?

    private var currentAppearance: ColorScheme? {
        switch selectedAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }

    private var appearanceIcon: String {
        switch selectedAppearance {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled" // system
        }
    }

    private var appearanceTitle: String {
        switch selectedAppearance {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "System"
        }
    }

    private var imagesSignature: [UUID] {
        model.project.images
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.id }
    }

    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content container WITHOUT the bottom menu bar
            VStack(spacing: 0) {
                header
                Divider()
                controls
                Divider()
                thumbnails
            }
            
            // Complete replacement of the bottom area with our custom floating bar
            bottomMenuBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .zIndex(100) // Ensure it's above everything else
        }
        .ignoresSafeArea(.container, edges: .bottom) // Allow content to extend to bottom edge
        .onAppear {
            if !haveCapturedOriginal {
                sortImagesByFolderThenName()
                captureOriginalOrderIfNeeded()
            }
            setupShiftKeyMonitoring()
            setupUndoRedoKeyMonitoring()
            
            // NEW: Just add this observer
            NotificationCenter.default.addObserver(
                forName: .saveRepositionHistory,
                object: nil,
                queue: .main
            ) { _ in
                saveToHistory()
            }
        }
        .onDisappear {
            tearDownShiftKeyMonitoring()
            tearDownUndoRedoKeyMonitoring()
            // Clean up color panel observer
            if let observer = colorPanelObserver {
                NotificationCenter.default.removeObserver(observer)
                colorPanelObserver = nil
            }
            // Close color panel if open
            if NSColorPanel.shared.isVisible {
                NSColorPanel.shared.close()
            }
        }
        .onChange(of: model.project.images.map(\.id)) { _, _ in
            captureOriginalOrderIfNeeded(forceIfIDsChanged: true)
        }
        .alert("Are you sure you want to reset order?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Order", role: .destructive) { resetToOriginalOrder() }
        } message: {
            Text("This will restore the original order and re-enable all items.")
        }
        .sheet(item: $repositionItem) { item in
            DragRepositionSheet(item: item, model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        
        // Separate full image view handling
        .overlay {
            if showFullImageView, let item = fullViewItem {
                FullImageView(
                    item: item,
                    model: model,
                    allImages: displayItems,
                    onNavigate: { newItem in
                        fullViewItem = newItem
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showFullImageView = false
                        }
                        fullViewItem = nil
                    }
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .preferredColorScheme(currentAppearance)
    }

    // MARK: - Header
    

    var enabledImageCount: Int {
        model.project.images.filter { !$0.disabled }.count
    }

    // MARK: - Controls (Updated with background color selector and border slider)
    
    
    // MARK: - Bottom Menu Bar
    
    // MARK: - Grid
    
    
    

    var displayItems: [ProjectImage] {
        let sorted = model.project.images.sorted { $0.orderIndex < $1.orderIndex }
        return showDisabled ? sorted : sorted.filter { !$0.disabled }
    }

    // MARK: - Shift Key Monitoring
    private func setupShiftKeyMonitoring() {
        shiftKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let isShiftCurrentlyPressed = event.modifierFlags.contains(.shift)
            
            if isShiftCurrentlyPressed != isShiftPressed {
                DispatchQueue.main.async {
                    isShiftPressed = isShiftCurrentlyPressed
                    if !isShiftPressed {
                        hoveredItemID = nil // Clear hover when shift is released
                    }
                }
            }
            
            return event
        }
    }
    
    private func tearDownShiftKeyMonitoring() {
        if let monitor = shiftKeyMonitor {
            NSEvent.removeMonitor(monitor)
            shiftKeyMonitor = nil
        }
    }
    
    // MARK: - Undo/Redo Key Monitoring

    private func setupUndoRedoKeyMonitoring() {
        undoRedoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Check for Command+Z (Undo)
            if event.keyCode == 6 && event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) { // 'z' key
                if historyManager.canUndo {
                    DispatchQueue.main.async {
                        performUndo()
                    }
                    return nil // Consume the event
                }
            }
            // Check for Command+Shift+Z (Redo)
            else if event.keyCode == 6 && event.modifierFlags.contains([.command, .shift]) { // 'z' key with shift
                if historyManager.canRedo {
                    DispatchQueue.main.async {
                        performRedo()
                    }
                    return nil // Consume the event
                }
            }
            return event // Allow other keys to pass through
        }
    }

    private func tearDownUndoRedoKeyMonitoring() {
        if let monitor = undoRedoKeyMonitor {
            NSEvent.removeMonitor(monitor)
            undoRedoKeyMonitor = nil
        }
    }
    
    // MARK: - Undo/Redo Functions
    func performUndo() {
        guard let previousImages = historyManager.undo() else { return }
        model.project.images = previousImages
    }

    func performRedo() {
        guard let nextImages = historyManager.redo() else { return }
        model.project.images = nextImages
    }

    func saveToHistory() {
        // Fixed: Use proper method to save snapshot
        historyManager.save(model.project.images)
    }

    // Update your existing functions to save history:
    func toggleDisabled(_ item: ProjectImage) {
        saveToHistory() // Save state before change
        
        guard let idx = model.project.images.firstIndex(where: { $0.id == item.id }) else { return }
        model.project.images[idx].disabled.toggle()
        
        if autoSendToEnd && model.project.images[idx].disabled {
            moveDisabledToEnd()
        }
    }

    func selectAll() {
        saveToHistory() // Save state before change
        
        for i in model.project.images.indices {
            model.project.images[i].disabled = false
        }
    }

    func deselectAll() {
        saveToHistory() // Save state before change
        
        for i in model.project.images.indices {
            model.project.images[i].disabled = true
        }
        
        if autoSendToEnd {
            moveDisabledToEnd()
        }
    }

    func randomizeOrder() {
        guard !model.project.images.isEmpty else { return }
        
        saveToHistory() // Save state before change
        
        // Separate enabled and disabled images
        let sorted = model.project.images.sorted { $0.orderIndex < $1.orderIndex }
        let enabled = sorted.filter { !$0.disabled }
        let disabled = sorted.filter { $0.disabled }
        
        // Randomize only the enabled images
        var randomizedEnabled = enabled
        randomizedEnabled.shuffle()
        
        // Combine: randomized enabled images first, then disabled images at the end
        let finalOrder = randomizedEnabled + disabled
        
        // Update order indices
        model.project.images = finalOrder.enumerated().map { i, item in
            var updatedItem = item
            updatedItem.orderIndex = i
            return updatedItem
        }
    }
    // MARK: - Helper functions
    private func sortImagesByFolderThenName() {
        guard !model.project.images.isEmpty else { return }
        func parentFolderName(for url: URL) -> String { url.deletingLastPathComponent().lastPathComponent }
        func fileName(for url: URL) -> String { url.lastPathComponent }
        let sorted = model.project.images.sorted { a, b in
            let fa = parentFolderName(for: a.url)
            let fb = parentFolderName(for: b.url)
            if fa.caseInsensitiveCompare(fb) != .orderedSame {
                return fa.caseInsensitiveCompare(fb) == .orderedAscending
            } else {
                return fileName(for: a.url).localizedStandardCompare(fileName(for: b.url)) == .orderedAscending
            }
        }
        model.project.images = sorted.enumerated().map { i, it in
            var copy = it
            copy.orderIndex = i
            return copy
        }
    }


    private func resetToOriginalOrder() {
        guard !originalOrderIDs.isEmpty else { return }
        var byID: [UUID: ProjectImage] = [:]
        for img in model.project.images { byID[img.id] = img }
        var rebuilt: [ProjectImage] = []
        rebuilt.reserveCapacity(originalOrderIDs.count)
        for (i, id) in originalOrderIDs.enumerated() {
            if var it = byID[id] {
                it.disabled = false
                it.orderIndex = i
                it.offsetX = 0.0
                it.offsetY = 0.0
                rebuilt.append(it)
            }
        }
        model.project.images = rebuilt
    }

 
    private func moveDisabledToEnd() {
        // First, disable any currently enabled images that we want to send to end
        // (This step is optional - remove if you only want to move already disabled images)
        
        // Get current order
        let sorted = model.project.images.sorted { $0.orderIndex < $1.orderIndex }
        
        // Separate enabled and disabled images
        let enabled = sorted.filter { !$0.disabled }
        let disabled = sorted.filter { $0.disabled }
        
        // Reorder: enabled images first, then disabled images at the end
        let reordered = enabled + disabled
        
        // Update the order indices and ensure disabled images stay disabled
        model.project.images = reordered.enumerated().map { i, item in
            var updatedItem = item
            updatedItem.orderIndex = i
            // Keep disabled images disabled (this line ensures they stay disabled)
            // updatedItem.disabled = disabled.contains { $0.id == item.id } ? true : updatedItem.disabled
            return updatedItem
        }
    }
    
    // MARK: - Capture Original Order
    private func captureOriginalOrderIfNeeded(forceIfIDsChanged: Bool = false) {
        // Only capture if we haven't already captured the original order
        if !haveCapturedOriginal || (forceIfIDsChanged && originalOrderIDs.isEmpty) {
            // Store the current order as the original order
            originalOrderIDs = model.project.images
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { $0.id }
            haveCapturedOriginal = true
        }
    }
    
    private func resetPosition(_ item: ProjectImage) {
        guard let idx = model.project.images.firstIndex(where: { $0.id == item.id }) else { return }
        model.project.images[idx].offsetX = 0.0
        model.project.images[idx].offsetY = 0.0
    }
    // MARK: - Mac Color Picker Function
    func openMacColorPicker() {
        let colorPanel = NSColorPanel.shared
        colorPanel.color = NSColor(backgroundColor)
        colorPanel.showsAlpha = false
        colorPanel.isContinuous = true
        
        // Show the color panel
        colorPanel.makeKeyAndOrderFront(nil)
        
        // Create a simple observer for color changes (no weak self needed in structs)
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: colorPanel,
            queue: .main
        ) { _ in
            backgroundColor = Color(nsColor: colorPanel.color)
            selectedColorOption = .custom
            syncBackgroundColorToProject()
        }
    }
}
