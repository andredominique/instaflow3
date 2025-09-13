import SwiftUI
import AppKit

struct SelectionsView: View {
    @EnvironmentObject var model: AppModel
    // Store autoSendToEnd preference in AppStorage to persist between views
    @AppStorage("autoSendToEnd") var autoSendToEnd: Bool = true
    
    @State var colorPanelObserver: NSObjectProtocol?
    @State var borderWidth: Double = 0.0
    // Add this line with your other @State variables (around line 85)
    @State var undoRedoKeyMonitor: Any?
    // NEW: History manager
    @StateObject var historyManager = HistoryManager()
    
    // NEW: System appearance toggle - ADD THESE LINES
    @AppStorage("selectedAppearance") var selectedAppearance: String = "light"
    @Environment(\.colorScheme) var systemColorScheme
    
    // Store showDisabled preference in AppStorage to persist between views
    @AppStorage("showDisabledImages") var showDisabled: Bool = true
    
    // Store the selected color option name in AppStorage
    @AppStorage("selectedColorOptionName") var selectedColorOptionName: String = "black"
    
    // Store RGB components of custom color in AppStorage
    @AppStorage("customColorRed") var customColorRed: Double = 0.0
    @AppStorage("customColorGreen") var customColorGreen: Double = 0.0
    @AppStorage("customColorBlue") var customColorBlue: Double = 0.0
    
    // UI state
    @State var draggingID: UUID? = nil
    @State var columns: Int = 5
    @State var disabledOverlayOpacity: Double = 0.5
    @State var showResetConfirm = false
    
    // NEW: Background color for when zoom to fill is disabled
    @State var backgroundColor = Color.black // Default background color is black

    // Helper to sync backgroundColor to global project color
    private func syncBackgroundColorToProject() {
        let ns = NSColor(backgroundColor)
        let colorData = ColorData(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            opacity: 1
        )
        // Update both border colors at the same time
        model.project.reelBorderColor = colorData
        model.project.carouselBorderColor = colorData
    }
    
    // Store selectedColorOption as a State variable, and sync with AppStorage when it changes
    @State var selectedColorOption: ColorOption = .black
    
    // SIMPLIFIED: Direct reposition sheet state
    @State var repositionItem: ProjectImage? = nil
    
    // NEW: Full image view state - changed to Bool + item tracking
    @State var showFullImageView = false
    @State var fullViewItem: ProjectImage? = nil

    // Capture the "original order after coming from Folders"
    @State var originalOrderIDs: [UUID] = []
    // We keep this as @State for local view handling, but use the model.project.hasCustomOrder for persistence
    @State var haveCapturedOriginal = false
    
    // Shift key state and hover tracking for repositioning and zooming
    @State var isShiftPressed = false
    @State var isCommandPressed = false
    @State var hoveredItemID: UUID? = nil
    @State var shiftKeyMonitor: Any?
    @State var scrollGestureMonitor: Any?
    
    // Constants for zoom control
    private let minZoomScale: Double = 0.5  // 50% of original size
    private let maxZoomScale: Double = 3.0   // 300% of original size
    private let zoomStep: Double = 0.1      // 10% per scroll unit

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
            // Only sort and capture original order if this is the first time loading
            if !model.project.hasCustomOrder {
                sortImagesByFolderThenName()
                captureOriginalOrderIfNeeded()
            }
            
            // Initialize background color and selectedColorOption from stored preferences
            initColorFromPreferences()
            
            setupShiftKeyMonitoring()
            setupUndoRedoKeyMonitoring()
            
            // Save history when position changes occur
            NotificationCenter.default.addObserver(
                forName: .saveRepositionHistory,
                object: nil,
                queue: .main
            ) { notification in
                // Only save if we're actively modifying
                if let _ = notification.object as? AppModel {
                    saveToHistory()
                }
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
        // Add listener for selectedColorOption changes to save to AppStorage
        .onChange(of: selectedColorOption) { _, newValue in
            // Save the color option name
            switch newValue {
            case .black:
                selectedColorOptionName = "black"
            case .white:
                selectedColorOptionName = "white"
            case .custom:
                selectedColorOptionName = "custom"
            }
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

    // Initialize the background color from saved preferences
    private func initColorFromPreferences() {
        // First set the selectedColorOption based on the saved name
        switch selectedColorOptionName {
        case "black":
            selectedColorOption = .black
            backgroundColor = .black
        case "white":
            selectedColorOption = .white
            backgroundColor = .white
        case "custom":
            selectedColorOption = .custom
            backgroundColor = Color(red: customColorRed, green: customColorGreen, blue: customColorBlue)
        default:
            selectedColorOption = .black
            backgroundColor = .black
        }
        
        // Sync to project on initialization
        syncBackgroundColorToProject()
    }

    var enabledImageCount: Int {
        model.project.images.filter { !$0.disabled }.count
    }

    var displayItems: [ProjectImage] {
        let sorted = model.project.images.sorted { $0.orderIndex < $1.orderIndex }
        return showDisabled ? sorted : sorted.filter { !$0.disabled }
    }

    // MARK: - Shift Key and Scroll Monitoring
    private func setupShiftKeyMonitoring() {
        // Monitor shift key state
        shiftKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let isShiftCurrentlyPressed = event.modifierFlags.contains(.shift)
            let isCommandCurrentlyPressed = event.modifierFlags.contains(.command)

            if isShiftCurrentlyPressed != isShiftPressed || isCommandCurrentlyPressed != isCommandPressed {
                DispatchQueue.main.async {
                    isShiftPressed = isShiftCurrentlyPressed
                    isCommandPressed = isCommandCurrentlyPressed
                    if !isShiftPressed {
                        hoveredItemID = nil // Clear hover when shift is released
                    }
                }
            }
            return event
        }
        
        // Monitor scroll gestures
        scrollGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            // Enable zoom if Command is pressed and hovering over a thumbnail
            if event.modifierFlags.contains(.command) && hoveredItemID != nil {
                DispatchQueue.main.async {
                    handleZoomGesture(deltaY: event.deltaY, forImageId: hoveredItemID!)
                }
                return nil // Consume the event when we're zooming
            }
            return event // Pass through all other scroll events
        }
    }
    
    private func tearDownShiftKeyMonitoring() {
        if let monitor = shiftKeyMonitor {
            NSEvent.removeMonitor(monitor)
            shiftKeyMonitor = nil
        }
        if let monitor = scrollGestureMonitor {
            NSEvent.removeMonitor(monitor)
            scrollGestureMonitor = nil
        }
    }
    
    private func handleZoomGesture(deltaY: CGFloat, forImageId: UUID) {
        // Save state before zoom
        saveToHistory()
        
        // Find the image
        guard let idx = model.project.images.firstIndex(where: { $0.id == forImageId }) else { return }
        
        // Calculate new zoom scale (negative deltaY means scroll up/zoom in)
        let zoomDelta = -Double(deltaY) * zoomStep
        var newScale = model.project.images[idx].zoomScale + zoomDelta
        
        // Clamp to min/max values
        newScale = min(max(newScale, minZoomScale), maxZoomScale)
        
        // Apply the new zoom scale
        model.project.images[idx].zoomScale = newScale
        model.objectWillChange.send()
        
        // Save state after zoom
        saveToHistory()
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
        historyManager.save(model.project.images)
    }

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
        // Re-sort all images by filename to restore original order
        var allImages = model.project.images
        allImages.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        
        // Re-enable all images and reset their order and position
        for i in allImages.indices {
            var img = allImages[i]
            img.disabled = false  // Re-enable the image
            img.orderIndex = i    // Reset the order
            img.offsetX = 0.0     // Reset position
            img.offsetY = 0.0
            allImages[i] = img
        }
        
        // Reset custom order flag since we're back to original order
        model.project.hasCustomOrder = false
        
        // Update the model with reset images
        model.project.images = allImages
        
        // Clear original order IDs since we're back to default
        originalOrderIDs = []
        haveCapturedOriginal = false
    }

    private func moveDisabledToEnd() {
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
            return updatedItem
        }
        
        // Mark that we have a custom order now
        model.project.hasCustomOrder = true
    }
    
    // MARK: - Capture Original Order
    private func captureOriginalOrderIfNeeded(forceIfIDsChanged: Bool = false) {
        if !haveCapturedOriginal || (forceIfIDsChanged && originalOrderIDs.isEmpty) {
            originalOrderIDs = model.project.images
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { $0.id }
            model.project.hasCustomOrder = true
            haveCapturedOriginal = true
        }
    }
    
    private func resetPosition(_ item: ProjectImage) {
        // Save the current state to history before resetting
        saveToHistory()
        guard let idx = model.project.images.firstIndex(where: { $0.id == item.id }) else { return }
        model.project.images[idx].offsetX = 0.0
        model.project.images[idx].offsetY = 0.0
        model.objectWillChange.send()
        saveToHistory() // Save the reset state
    }

    // MARK: - Mac Color Picker Function
    func openMacColorPicker() {
        let colorPanel = NSColorPanel.shared
        colorPanel.color = NSColor(backgroundColor)
        colorPanel.showsAlpha = false
        colorPanel.isContinuous = true
        
        // Show the color panel
        colorPanel.makeKeyAndOrderFront(nil)
        
        // Create a simple observer for color changes
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: colorPanel,
            queue: .main
        ) { _ in
            let nsColor = colorPanel.color
            backgroundColor = Color(nsColor: nsColor)
            
            // Save the custom color components to AppStorage
            customColorRed = Double(nsColor.redComponent)
            customColorGreen = Double(nsColor.greenComponent)
            customColorBlue = Double(nsColor.blueComponent)
            
            // Update the selected option
            selectedColorOption = .custom
            selectedColorOptionName = "custom"
            
            // Sync to both aspect ratios
            let colorData = ColorData(
                red: Double(nsColor.redComponent),
                green: Double(nsColor.greenComponent),
                blue: Double(nsColor.blueComponent),
                opacity: 1
            )
            // Update both border colors at the same time
            model.project.reelBorderColor = colorData
            model.project.carouselBorderColor = colorData
        }
    }
}