import SwiftUI
import AppKit
import AVFoundation

struct FinalPreviewExport {
    @MainActor
    static func render(item: ProjectImage,
                       model: AppModel,
                       size: CGSize,
                       imageProvider: (ProjectImage) -> NSImage?) -> NSImage {
        let borderWidth = model.project.selectionBorderWidth
        let bgColor = NSColor(model.project.selectionBackgroundColor)
        let aspect = model.project.aspect.aspect

        let image = NSImage(size: size)
        image.lockFocus()

        // Fill background
        bgColor.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        // Inset the canvas by border width for the image
        let imageInset = CGFloat(borderWidth)
        let imageRect = AVMakeRect(
            aspectRatio: NSSize(width: aspect, height: 1.0),
            insideRect: CGRect(origin: .zero, size: size).insetBy(dx: imageInset, dy: imageInset)
        )
        // Draw the photo with offsets
        if let nsImg = imageProvider(item) {
            let imageAspect = nsImg.size.width / nsImg.size.height
            let containerAspect = imageRect.width / imageRect.height
            
            var drawRect = imageRect
            
            // Calculate offsets
            let maxOffsetX: CGFloat
            if imageAspect > containerAspect {
                let imageWidth = drawRect.height * imageAspect
                let overflow = imageWidth - drawRect.width
                maxOffsetX = overflow / 2
            } else {
                maxOffsetX = 0
            }
            
            let maxOffsetY: CGFloat
            if imageAspect < containerAspect {
                let imageHeight = drawRect.width / imageAspect
                let overflow = imageHeight - drawRect.height
                maxOffsetY = overflow / 2
            } else {
                maxOffsetY = 0
            }
            
            // Apply offsets
            drawRect.origin.x += CGFloat(item.offsetX) * maxOffsetX
            drawRect.origin.y += CGFloat(item.offsetY) * maxOffsetY
            
            nsImg.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        // Draw the border on a rect inset by half border width from the canvas
        if borderWidth > 0 {
            let borderRect = CGRect(origin: .zero, size: size).insetBy(dx: CGFloat(borderWidth) / 2, dy: CGFloat(borderWidth) / 2)
            let path = NSBezierPath(
                roundedRect: borderRect,
                xRadius: max(0, 10 - borderWidth),
                yRadius: max(0, 10 - borderWidth)
            )
            bgColor.setStroke()
            path.lineWidth = CGFloat(borderWidth)
            path.stroke()
        }

        image.unlockFocus()
        return image
    }
}
