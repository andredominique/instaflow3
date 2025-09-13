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
    
    private var imageAspect: CGFloat {
        guard let nsImage = nsImage else { return 1.0 }
        return nsImage.size.width / nsImage.size.height
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Base layer for hover detection
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        onHoverChange(hovering)
                    }
                    // Detect drags but allow other events to pass through
                    .simultaneousGesture(
                        DragGesture(coordinateSpace: .local)
                            .onChanged { value in
                                guard zoomToFill, nsImage != nil else { return }
                                
                                if !isDragging {
                                    isDragging = true
                                    dragStart = value.startLocation
                                    startOffsetX = item.offsetX
                                    startOffsetY = item.offsetY
                                    
                                    // Don't need history save here since setCropOffset handles it
                                }
                                
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
                                
                                // Update the model in real-time (history saving is handled in setCropOffset)
                                model.setCropOffset(for: item.id, offsetX: newOffsetX, offsetY: newOffsetY)
                            }
                            .onEnded { _ in
                                isDragging = false
                                // No need for final history save since setCropOffset handles it
                            }
                    )
                    )
                
                // Reposition icon - only show when hovering and zoomToFill is enabled
                if isHovered && zoomToFill {
                    VStack {
                        HStack {
                            Spacer()
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