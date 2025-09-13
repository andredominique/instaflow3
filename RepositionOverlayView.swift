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

    @State private var nsImage: NSImage?
    
    init(item: ProjectImage, model: AppModel, aspect: CGFloat, zoomToFill: Bool, isHovered: Bool, onHoverChange: @escaping (Bool) -> Void) {
        self.item = item
        self.model = model
        self.aspect = aspect
        self.zoomToFill = zoomToFill
        self.isHovered = isHovered
        self.onHoverChange = onHoverChange
    }
    
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
                    .gesture(
                        DragGesture(coordinateSpace: .local)
                            .onChanged { value in
                                guard nsImage != nil else { return }
                                
                                if !isDragging {
                                    isDragging = true
                                    dragStart = value.startLocation
                                    
                                    // Initialize drag position
                                    startOffsetX = item.offsetX
                                    startOffsetY = item.offsetY
                                    // Save history for position changes
                                    NotificationCenter.default.post(
                                        name: .saveRepositionHistory,
                                        object: model
                                    )
                                }
                                
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
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                
                // Show appropriate icon based on mode
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            // Reposition mode icon
                            Image(systemName: "move.3d")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                    .allowsHitTesting(false) // Don't interfere with drag gesture
                }
            }
            .onAppear {
                if nsImage == nil {
                    nsImage = NSImage(contentsOf: item.url)
                }
                
                // No need for command key monitoring here
                // It's now handled centrally in SelectionsView.Core
            }
            .onDisappear {
                // Cleanup handled elsewhere
            }
        }
    }
    
    private func maxHorizontalOffset(for containerSize: CGSize) -> CGFloat {
        guard self.zoomToFill && self.imageAspect > self.aspect else { return 0 }
        let imageWidth = containerSize.height * self.imageAspect
        return (imageWidth - containerSize.width) / 2
    }
    
    private func maxVerticalOffset(for containerSize: CGSize) -> CGFloat {
        guard self.zoomToFill && self.imageAspect < self.aspect else { return 0 }
        let imageHeight = containerSize.width / self.imageAspect
        return (imageHeight - containerSize.height) / 2
    }
}