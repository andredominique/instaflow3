import SwiftUI
import AppKit

struct ThumbView: View {
    let url: URL
    let aspect: CGFloat
    let offsetX: Double
    let offsetY: Double
    let zoomToFill: Bool
    let backgroundColor: Color
    let borderWidth: Double
    @State private var nsImage: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Background color (visible when not zooming to fill OR when there's a border)
                if !zoomToFill || borderWidth > 0 {
                    backgroundColor
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                if let img = nsImage {
                    // Calculate the content area after accounting for border
                    let contentSize = CGSize(
                        width: proxy.size.width - (CGFloat(borderWidth) * 2),
                        height: proxy.size.height - (CGFloat(borderWidth) * 2)
                    )
                    
                    PositionedImageView(
                        image: img,
                        containerSize: contentSize, // Use reduced size for border
                        aspect: aspect,
                        offsetX: offsetX,
                        offsetY: offsetY,
                        zoomToFill: zoomToFill
                    )
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(
                        cornerRadius: max(0, 10 - borderWidth),
                        style: .continuous
                    ))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
                        .overlay(ProgressView())
                }
                
                // Border overlay when border width > 0
                if borderWidth > 0 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(backgroundColor, lineWidth: CGFloat(borderWidth))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(radius: 1)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .task {
            if nsImage == nil, let img = NSImage(contentsOf: url) {
                nsImage = img
            }
        }
    }
}