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

        // Inset the canvas by border width first
        let canvasRect = CGRect(origin: .zero, size: size).insetBy(dx: CGFloat(borderWidth), dy: CGFloat(borderWidth))
        // Fit aspect ratio inside the inset canvas
        let imageRect = AVMakeRect(
            aspectRatio: NSSize(width: aspect, height: 1.0),
            insideRect: canvasRect
        )
        // Draw the photo
        if let nsImg = imageProvider(item) {
            nsImg.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        // Draw the border exactly on the image rect
        if borderWidth > 0 {
            let path = NSBezierPath(
                roundedRect: imageRect,
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
