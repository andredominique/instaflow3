import SwiftUI
import AppKit

struct FullImageView: View {
    @State private var currentItem: ProjectImage
    let model: AppModel
    let allImages: [ProjectImage]
    let onNavigate: (ProjectImage) -> Void
    let onDismiss: () -> Void
    
    @State private var nsImage: NSImage?
    @State private var isDisabled: Bool
    @State private var showImageInfo = false
    @State private var viewMode: ViewMode = .full
    
    // NEW: Shift key tracking
    @State private var isShiftPressed = false
    @State private var shiftKeyMonitor: Any?
    
    // NEW: Enhanced keyboard event monitoring with higher priority
    @State private var localKeyboardMonitor: Any?
    @State private var globalKeyboardMonitor: Any?
    
    // NEW: Reposition aspect ratio for shift mode (gets set from model.project.aspect, defaults to 9:16)
    @State private var repositionAspectRatio: CGFloat = 9.0/16.0
    @State private var repositionViewMode: ViewMode = .crop9x16
    
    // Reposition state for shift mode
    @State private var repositionOffsetX: Double = 0.0
    @State private var repositionOffsetY: Double = 0.0
    @State private var isDragging = false
    @State private var hasUnsavedChanges = false
    
    // NEW: Remember reposition state for each image
    @State private var repositionStates: [UUID: (offsetX: Double, offsetY: Double)] = [:]
    
    init(item: ProjectImage, model: AppModel, allImages: [ProjectImage], onNavigate: @escaping (ProjectImage) -> Void, onDismiss: @escaping () -> Void) {
        self._currentItem = State(initialValue: item)
        self.model = model
        self.allImages = allImages
        self.onNavigate = onNavigate
        self.onDismiss = onDismiss
        self._isDisabled = State(initialValue: item.disabled)
    }
    
    private var currentIndex: Int {
        allImages.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }
    
    private var canGoToPrevious: Bool {
        currentIndex > 0
    }
    
    private var canGoToNext: Bool {
        currentIndex < allImages.count - 1
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background overlay - More transparent (80% transparent = 0.2 opacity)
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .onTapGesture {
                        handleDismiss()
                    }
                
                // Main content area
                VStack(spacing: 0) {
                    // Header - More transparent background
                    headerView
                        .background(Color.black.opacity(0.0))
                        .onTapGesture {
                            // Prevent dismiss when clicking on header
                        }
                    
                    // Main image area with navigation
                    HStack(spacing: 0) {
                        // Previous button
                        Button {
                            navigateToPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white.opacity(canGoToPrevious ? 1.0 : 0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoToPrevious)
                        .frame(width: 60)
                        .onTapGesture {
                            // Prevent dismiss when clicking on button
                        }
                        
                        // Main image area
                        ZStack {
                            if let image = nsImage {
                                imageDisplayView(image: image, geometry: geometry)
                                    .onTapGesture {
                                        // Prevent dismiss when clicking on image
                                    }
                            } else {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                    Text("Loading image...")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .onTapGesture {
                                    // Prevent dismiss when clicking on loading indicator
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Next button
                        Button {
                            navigateToNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white.opacity(canGoToNext ? 1.0 : 0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoToNext)
                        .frame(width: 60)
                        .onTapGesture {
                            // Prevent dismiss when clicking on button
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Bottom toolbar - More transparent background
                    bottomToolbar(geometry: geometry)
                        .background(Color.black.opacity(0.0))
                        .onTapGesture {
                            // Prevent dismiss when clicking on toolbar
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(true) // Make this view focusable to receive key events
        .onAppear {
            loadCurrentImage()
            setupKeyboardMonitoring()
            setRepositionAspectFromProject()
        }
        .onDisappear {
            tearDownKeyboardMonitoring()
        }
        .onChange(of: currentItem.id) { _, _ in
            loadCurrentImage()
            loadRepositionStateForCurrentImage()
            hasUnsavedChanges = false
        }
        .onChange(of: isDisabled) { _, newValue in
            updateItemDisabledState(newValue)
        }
        .onChange(of: isShiftPressed) { _, newValue in
            if newValue {
                // Shift pressed - enter reposition mode
                loadRepositionStateForCurrentImage()
                hasUnsavedChanges = false
            } else {
                // Shift released - save changes if any
                if hasUnsavedChanges {
                    saveRepositionStateForCurrentImage()
                    applyReposition()
                }
            }
        }
        .onChange(of: repositionOffsetX) { _, _ in
            if isShiftPressed {
                hasUnsavedChanges = (repositionOffsetX != currentItem.offsetX || repositionOffsetY != currentItem.offsetY)
            }
        }
        .onChange(of: repositionOffsetY) { _, _ in
            if isShiftPressed {
                hasUnsavedChanges = (repositionOffsetX != currentItem.offsetX || repositionOffsetY != currentItem.offsetY)
            }
        }
    }
    
    @ViewBuilder
    private func imageDisplayView(image: NSImage, geometry: GeometryProxy) -> some View {
        // Center the content in the available space
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                ZStack {
                    if isShiftPressed {
                        // Shift mode - ALWAYS show repositioning view with cropped aspect
                        repositionImageView(image: image, geometry: geometry)
                    } else {
                        // Normal mode - show full image
                        normalImageView(image: image, geometry: geometry)
                    }
                }
                .overlay(disabledOverlay)
                .animation(.easeInOut(duration: 0.2), value: isShiftPressed)
                
                Spacer()
            }
            Spacer()
        }
    }
    
    private func normalImageView(image: NSImage, geometry: GeometryProxy) -> some View {
        // Calculate size based on available space
        let availableWidth = geometry.size.width - 120 // Account for navigation buttons
        let availableHeight = geometry.size.height - 160 // Account for header/footer
        
        let imageAspectRatio = image.size.width / image.size.height
        
        // Calculate dimensions that fit within available space
        let maxWidth = availableWidth * 0.9
        let maxHeight = availableHeight * 0.9
        
        let widthBasedHeight = maxWidth / imageAspectRatio
        let heightBasedWidth = maxHeight * imageAspectRatio
        
        let finalDimensions: (width: CGFloat, height: CGFloat) = {
            if widthBasedHeight <= maxHeight {
                return (maxWidth, widthBasedHeight)
            } else {
                return (heightBasedWidth, maxHeight)
            }
        }()
        
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: finalDimensions.width, height: finalDimensions.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
    }
    
    private func repositionImageView(image: NSImage, geometry: GeometryProxy) -> some View {
        // Calculate size similar to normal view
        let availableWidth = geometry.size.width - 120
        let availableHeight = geometry.size.height - 160
        
        let imageAspectRatio = image.size.width / image.size.height
        
        let maxWidth = availableWidth * 0.9
        let maxHeight = availableHeight * 0.9
        
        let widthBasedHeight = maxWidth / imageAspectRatio
        let heightBasedWidth = maxHeight * imageAspectRatio
        
        let finalDimensions: (width: CGFloat, height: CGFloat) = {
            if widthBasedHeight <= maxHeight {
                return (maxWidth, widthBasedHeight)
            } else {
                return (heightBasedWidth, maxHeight)
            }
        }()
        
        return RepositionDraggableView(
            image: image,
            aspect: repositionAspectRatio,
            offsetX: $repositionOffsetX,
            offsetY: $repositionOffsetY,
            isDragging: $isDragging,
            forceShowCropped: true // ALWAYS show cropped view in shift mode
        )
        .frame(width: finalDimensions.width, height: finalDimensions.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 12)
    }
    
    @ViewBuilder
    private var disabledOverlay: some View {
        if isDisabled {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.8))
                )
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(currentItem.url.lastPathComponent)
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text("(\(currentIndex + 1) of \(allImages.count))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    if isShiftPressed {
                        HStack(spacing: 4) {
                            Text("• Reposition Mode")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("(← → to navigate)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                    }
                }
                
                Text(currentItem.url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button {
                showImageInfo.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.white)
            }
            .help("Show image information")
            .disabled(isShiftPressed)
            
            Button {
                handleDismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.white)
            }
            .help("Close (Esc or Enter)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private func bottomToolbar(geometry: GeometryProxy) -> some View {
        HStack(spacing: 16) {
            // Left section: Enable/Disable button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDisabled.toggle()
                }
            } label: {
                Label(
                    isDisabled ? "Disabled" : "Enabled",
                    systemImage: isDisabled ? "eye.slash" : "eye"
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(isDisabled ? .red : .green)
            .disabled(isShiftPressed)
            
            // Reposition controls
            if !isShiftPressed {
                Text("Hold Shift to reposition")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                repositionAspectRatioButtons
            }
            
            // Reset Position button (if needed)
            if currentItem.offsetX != 0.0 || currentItem.offsetY != 0.0 {
                Button {
                    resetPosition()
                } label: {
                    Label("Reset Position", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.white)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isShiftPressed)
            }
            
            Spacer()
            
            // Right section: Image info
            if showImageInfo {
                imageInfoView
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var repositionAspectRatioButtons: some View {
        HStack(spacing: 0) {
            ForEach([ViewMode.crop4x5, ViewMode.crop9x16], id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        repositionViewMode = mode
                        repositionAspectRatio = mode.aspectRatio ?? 9.0/16.0 // Default to 9:16
                    }
                } label: {
                    Text(mode.title)
                        .font(.caption2)
                        .fontWeight(repositionViewMode == mode ? .semibold : .regular)
                        .foregroundColor(repositionViewMode == mode ? .black : .white)
                        .frame(minWidth: 30, minHeight: 22)
                        .background(
                            repositionViewMode == mode ?
                            Color.white : Color.clear
                        )
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 0))
            }
        }
        .background(Color.white.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    
    private var imageInfoView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let image = nsImage {
                Text("Original: \(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Text("Aspect: \(String(format: "%.2f", image.size.width / image.size.height))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            Text("Crop: \(String(format: "%.2f", repositionAspectRatio))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            Text("Offset: (\(String(format: "%.1f", currentItem.offsetX)), \(String(format: "%.1f", currentItem.offsetY)))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    // MARK: - Helper functions
    
    private func setupKeyboardMonitoring() {
        // Set up local monitor with highest priority - this captures events before they reach the system
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let isShiftCurrentlyPressed = event.modifierFlags.contains(.shift)
            
            // Handle shift key changes
            if isShiftCurrentlyPressed != isShiftPressed {
                DispatchQueue.main.async {
                    isShiftPressed = isShiftCurrentlyPressed
                }
            }
            
            // Handle key presses - OVERRIDE app navigation when in full screen
            switch event.keyCode {
            case 123: // Left arrow
                DispatchQueue.main.async {
                    self.navigateToPrevious()
                }
                return nil // Consume the event to prevent app navigation
            case 124: // Right arrow
                DispatchQueue.main.async {
                    self.navigateToNext()
                }
                return nil // Consume the event to prevent app navigation
            case 53: // ESC
                DispatchQueue.main.async {
                    self.handleDismiss()
                }
                return nil // Consume the event
            case 36: // Enter
                DispatchQueue.main.async {
                    self.handleDismiss()
                }
                return nil // Consume the event
            default:
                return event // Allow other keys to pass through
            }
        }
        
        // Set up global monitor as backup for when the window doesn't have focus
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 123: // Left arrow
                DispatchQueue.main.async {
                    self.navigateToPrevious()
                }
            case 124: // Right arrow
                DispatchQueue.main.async {
                    self.navigateToNext()
                }
            case 53: // ESC
                DispatchQueue.main.async {
                    self.handleDismiss()
                }
            case 36: // Enter
                DispatchQueue.main.async {
                    self.handleDismiss()
                }
            default:
                break
            }
        }
    }
    
    private func tearDownKeyboardMonitoring() {
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyboardMonitor = nil
        }
        if let monitor = globalKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyboardMonitor = nil
        }
        if let monitor = shiftKeyMonitor {
            NSEvent.removeMonitor(monitor)
            shiftKeyMonitor = nil
        }
    }
    
    private func loadRepositionStateForCurrentImage() {
        if let savedState = repositionStates[currentItem.id] {
            repositionOffsetX = savedState.offsetX
            repositionOffsetY = savedState.offsetY
        } else {
            repositionOffsetX = currentItem.offsetX
            repositionOffsetY = currentItem.offsetY
        }
    }
    
    private func saveRepositionStateForCurrentImage() {
        repositionStates[currentItem.id] = (offsetX: repositionOffsetX, offsetY: repositionOffsetY)
    }
    
    private func setRepositionAspectFromProject() {
        // Always default to 9:16, but allow override from project if available
        if model.project.aspect == .feed4x5 {
            repositionAspectRatio = 4.0/5.0
            repositionViewMode = .crop4x5
        } else {
            repositionAspectRatio = 9.0/16.0 // DEFAULT TO 9:16
            repositionViewMode = .crop9x16
        }
    }
    
    private func navigateToPrevious() {
        guard canGoToPrevious else { return }
        
        if isShiftPressed && hasUnsavedChanges {
            saveRepositionStateForCurrentImage()
            applyReposition()
        }
        
        let newItem = allImages[currentIndex - 1]
        currentItem = newItem
        isDisabled = newItem.disabled
        onNavigate(newItem)
    }
    
    private func navigateToNext() {
        guard canGoToNext else { return }
        
        if isShiftPressed && hasUnsavedChanges {
            saveRepositionStateForCurrentImage()
            applyReposition()
        }
        
        let newItem = allImages[currentIndex + 1]
        currentItem = newItem
        isDisabled = newItem.disabled
        onNavigate(newItem)
    }
    
    private func handleDismiss() {
        if isShiftPressed && hasUnsavedChanges {
            saveRepositionStateForCurrentImage()
            applyReposition()
        }
        onDismiss()
    }
    
    private func applyReposition() {
        model.setCropOffset(for: currentItem.id, offsetX: repositionOffsetX, offsetY: repositionOffsetY)
        
        if let idx = model.project.images.firstIndex(where: { $0.id == currentItem.id }) {
            currentItem = model.project.images[idx]
        }
        
        hasUnsavedChanges = false
    }
    
    private func loadCurrentImage() {
        nsImage = NSImage(contentsOf: currentItem.url)
    }
    
    private func updateItemDisabledState(_ disabled: Bool) {
        guard let idx = model.project.images.firstIndex(where: { $0.id == currentItem.id }) else { return }
        model.project.images[idx].disabled = disabled
        currentItem.disabled = disabled
    }
    
    private func resetPosition() {
        guard let idx = model.project.images.firstIndex(where: { $0.id == currentItem.id }) else { return }
        model.project.images[idx].offsetX = 0.0
        model.project.images[idx].offsetY = 0.0
        currentItem.offsetX = 0.0
        currentItem.offsetY = 0.0
        
        repositionStates.removeValue(forKey: currentItem.id)
        repositionOffsetX = 0.0
        repositionOffsetY = 0.0
    }
}