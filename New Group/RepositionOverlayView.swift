import SwiftUI
import AppKit

struct RepositionOverlayView: View {
    let item: ProjectImage
    let model: AppModel
    let aspect: CGFloat
    let zoomToFill: Bool
    let isHovered: Bool
    let onHoverChange: (Bool) -> Void
    
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var startOffsetX: Double = 0
    @State private var startOffsetY: Double = 0
    @State private var startZoomScale: Double = 1.0
    @State private var nsImage: NSImage?
    @State private var isCommandPressed = false
    
    private var imageAspect: CGFloat {
        guard let nsImage = nsImage else { return 1.0 }
        return nsImage.size.width / nsImage.size.height
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Base layer for event handling
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        onHoverChange(hovering)
                    }
                    .onAppear {
                        // Setup command key monitor
                        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
                            isCommandPressed = event.modifierFlags.contains(.command)
                            return event
                        }
                    }
                    .gesture(
                            DragGesture(coordinateSpace: .local)
                                .onChanged { value in
                                guard nsImage != nil else { return }
                                
                                if !isDragging {
                                    isDragging = true
                                    dragStart = value.startLocation
                                    
                                    // Initialize based on current mode
                                    if isCommandPressed {
                                        startZoomScale = item.zoomScale
                                    } else {
                                        startOffsetX = item.offsetX
                                        startOffsetY = item.offsetY
                                        // Save history for position changes
                                        NotificationCenter.default.post(
                                            name: .saveRepositionHistory,
                                            object: model
                                        )
                                    }
                                }
                                
                                // Handle zoom if command is pressed
                                if isCommandPressed {
                                    let dragAmount = value.location.y - dragStart.y
                                    let zoomDelta = Double(dragAmount) / 100.0 // Adjust sensitivity
                                    let newScale = max(0.5, min(3.0, startZoomScale + zoomDelta))
                                    
                                    // Update zoom scale
                                    if let idx = model.project.images.firstIndex(where: { $0.id == item.id }) {
                                        model.project.images[idx].zoomScale = newScale
                                        model.objectWillChange.send()
                                    }
                                } else {
                                    // Handle repositioning
                                    let deltaX = value.location.x - dragStart.x
                                    let deltaY = value.location.y - dragStart.y
                                    
                                    let maxX = maxHorizontalOffset(for: proxy.size)
                                    let maxY = maxVerticalOffset(for: proxy.size)
                                    
                                    var newOffsetX = item.offsetX
                                    var newOffsetY = item.offsetY
                                    
                                    if maxX > 0 {
                                        let normalizedDeltaX = Double(deltaX / maxX)
                                        newOffsetX = max(-1.0, min(1.0, startOffsetX + normalizedDeltaX))
                                    }
                                    
                                    if maxY > 0 {
                                        let normalizedDeltaY = Double(deltaY / maxY)
                                        newOffsetY = max(-1.0, min(1.0, startOffsetY + normalizedDeltaY))
                                    }
                                    
                                    // Update position
                                    model.setCropOffset(for: item.id, offsetX: newOffsetX, offsetY: newOffsetY)
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                        )
                }
                
                // Show appropriate icon based on mode
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            if isCommandPressed {
                                // Zoom mode icon
                                Image(systemName: "magnifyingglass.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.green.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            } else {
                                // Reposition mode icon
                                Image(systemName: "move.3d")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                    .allowsHitTesting(false) // Don't interfere with drag gesture
                }
            }
        }
        .onAppear {
            if nsImage == nil {
                nsImage = NSImage(contentsOf: item.url)
            }
        }
    }
    
    private func maxHorizontalOffset(for containerSize: CGSize) -> CGFloat {
        guard zoomToFill && imageAspect > aspect else { return 0 }
        let imageWidth = containerSize.height * imageAspect
        return (imageWidth - containerSize.width) / 2
    }
    
    private func maxVerticalOffset(for containerSize: CGSize) -> CGFloat {
        guard zoomToFill && imageAspect < aspect else { return 0 }
        let imageHeight = containerSize.width / imageAspect
        return (imageHeight - containerSize.height) / 2
    }
}