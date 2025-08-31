import SwiftUI
import AppKit

struct PositionedImageView: View {
    let image: NSImage
    let containerSize: CGSize
    let aspect: CGFloat
    let offsetX: Double
    let offsetY: Double
    let zoomToFill: Bool
    
    private var imageAspect: CGFloat {
        image.size.width / image.size.height
    }
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: zoomToFill ? .fill : .fit)
            .frame(width: containerSize.width, height: containerSize.height)
            .offset(
                x: zoomToFill ? CGFloat(offsetX) * maxOffsetX : 0,
                y: zoomToFill ? CGFloat(offsetY) * maxOffsetY : 0
            )
            .clipped()
    }
    
    private var maxOffsetX: CGFloat {
        if imageAspect > aspect {
            let imageWidth = containerSize.height * imageAspect
            let overflow = imageWidth - containerSize.width
            return overflow / 2
        }
        return 0
    }
    
    private var maxOffsetY: CGFloat {
        if imageAspect < aspect {
            let imageHeight = containerSize.width / imageAspect
            let overflow = imageHeight - containerSize.height
            return overflow / 2
        }
        return 0
    }
}