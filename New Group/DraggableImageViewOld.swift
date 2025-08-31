import SwiftUI
import AppKit

struct DraggableImageViewOld: View {
    let url: URL
    let aspect: CGFloat
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    @Binding var isDragging: Bool
    let zoomToFill: Bool
    
    @State private var nsImage: NSImage?
    @State private var dragStart: CGPoint = .zero
    @State private var startOffsetX: Double = 0
    @State private var startOffsetY: Double = 0
    
    private var imageAspect: CGFloat {
        guard let nsImage = nsImage else { return 1.0 }
        return nsImage.size.width / nsImage.size.height
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = nsImage {
                    PositionedImageView(
                        image: image,
                        containerSize: geometry.size,
                        aspect: aspect,
                        offsetX: offsetX,
                        offsetY: offsetY,
                        zoomToFill: zoomToFill
                    )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
                        .overlay(ProgressView())
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        guard nsImage != nil, zoomToFill else { return }
                        
                        if !isDragging {
                            isDragging = true
                            dragStart = value.startLocation
                            startOffsetX = offsetX
                            startOffsetY = offsetY
                        }
                        
                        let deltaX = value.location.x - dragStart.x
                        let deltaY = value.location.y - dragStart.y
                        
                        let maxX = maxHorizontalOffset(for: geometry.size)
                        let maxY = maxVerticalOffset(for: geometry.size)
                        
                        if maxX > 0 {
                            let normalizedDeltaX = Double(deltaX / maxX)
                            offsetX = max(-1.0, min(1.0, startOffsetX + normalizedDeltaX))
                        }
                        
                        if maxY > 0 {
                            let normalizedDeltaY = Double(deltaY / maxY)
                            offsetY = max(-1.0, min(1.0, startOffsetY + normalizedDeltaY))
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .aspectRatio(aspect, contentMode: .fit)
        .onAppear {
            if nsImage == nil {
                nsImage = NSImage(contentsOf: url)
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