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

        // Compute rect with aspect
        let target = AVMakeRect(
            aspectRatio: NSSize(width: aspect, height: 1.0),
            insideRect: CGRect(origin: .zero, size: size)
        )

        // Draw the photo, inset by border thickness so it sits fully within the border
        var imageRect = target
        if borderWidth > 0 {
            imageRect = target.insetBy(dx: CGFloat(borderWidth), dy: CGFloat(borderWidth))
        }
        if let nsImg = imageProvider(item) {
            nsImg.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Border: draw just inside the image area
        if borderWidth > 0 {
            let rect = target.insetBy(dx: CGFloat(borderWidth) / 2, dy: CGFloat(borderWidth) / 2)
            let path = NSBezierPath(
                roundedRect: rect,
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
