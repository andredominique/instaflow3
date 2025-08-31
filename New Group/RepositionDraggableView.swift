import SwiftUI
import AppKit

struct RepositionDraggableView: View {
    let image: NSImage
    let aspect: CGFloat
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    @Binding var isDragging: Bool
    let forceShowCropped: Bool // NEW: Always show cropped view when true
    
    @State private var dragStart: CGPoint = .zero
    @State private var startOffsetX: Double = 0
    @State private var startOffsetY: Double = 0
    
    private var imageAspect: CGFloat {
        image.size.width / image.size.height
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background: Full image with current offset, faded
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .offset(
                        x: forceShowCropped ? CGFloat(offsetX) * maxOffsetX(for: geometry.size) : 0,
                        y: forceShowCropped ? CGFloat(offsetY) * maxOffsetY(for: geometry.size) : 0
                    )
                    .opacity(0.3)
                
                // Foreground: Cropped result preview with blue border (ALWAYS show when forceShowCropped is true)
                if forceShowCropped {
                    cropPreview(geometry: geometry)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        guard forceShowCropped else { return }
                        
                        if !isDragging {
                            isDragging = true
                            dragStart = value.startLocation
                            startOffsetX = offsetX
                            startOffsetY = offsetY
                        }
                        
                        let deltaX = value.location.x - dragStart.x
                        let deltaY = value.location.y - dragStart.y
                        
                        let maxX = maxOffsetX(for: geometry.size)
                        let maxY = maxOffsetY(for: geometry.size)
                        
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
    }
    
    @ViewBuilder
    private func cropPreview(geometry: GeometryProxy) -> some View {
        let containerSize = geometry.size
        let cropWidth = containerSize.height * aspect
        let cropHeight = containerSize.height
        
        PositionedImageView(
            image: image,
            containerSize: CGSize(width: cropWidth, height: cropHeight),
            aspect: aspect,
            offsetX: offsetX,
            offsetY: offsetY,
            zoomToFill: true // Always use zoom to fill for cropped preview
        )
        .frame(width: cropWidth, height: cropHeight)
        .position(x: containerSize.width / 2, y: containerSize.height / 2)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(Color.blue.opacity(isDragging ? 1.0 : 0.7), lineWidth: isDragging ? 4 : 3)
                .frame(width: cropWidth, height: cropHeight)
                .position(x: containerSize.width / 2, y: containerSize.height / 2)
        )
    }
    
    private func maxOffsetX(for containerSize: CGSize) -> CGFloat {
        if imageAspect > aspect {
            let imageWidth = containerSize.height * imageAspect
            let cropWidth = containerSize.height * aspect
            return (imageWidth - cropWidth) / 2
        }
        return 0
    }
    
    private func maxOffsetY(for containerSize: CGSize) -> CGFloat {
        if imageAspect < aspect {
            let imageHeight = containerSize.width / imageAspect
            let cropHeight = containerSize.width / aspect
            return (imageHeight - cropHeight) / 2
        }
        return 0
    }
}