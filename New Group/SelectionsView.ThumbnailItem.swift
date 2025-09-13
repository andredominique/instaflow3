//
// Auto-split: thumbnailItem
//
import SwiftUI
extension SelectionsView {
@ViewBuilder func thumbnailItem(_ item: ProjectImage, isCommandPressed: Bool, isShiftPressed: Bool) -> some View {
    let isReelAspect = model.project.aspect == .story9x16
    let bgColor = isReelAspect ? model.project.reelBorderColor.swiftUIColor : model.project.carouselBorderColor.swiftUIColor
    let borderPx = isReelAspect ? Double(model.project.reelBorderPx) : Double(model.project.carouselBorderPx)
    ZStack {
        if draggingID == item.id && !isShiftPressed {
            // Show placeholder when dragging for reorder
            bgColor
                .aspectRatio(model.project.aspect.aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(radius: 1)
        } else {
            ZStack {
                // Base thumbnail image with background color support
                ThumbView(
                    url: item.url,
                    aspect: model.project.aspect.aspect,
                    offsetX: item.offsetX,
                    offsetY: item.offsetY,
                    zoomToFill: model.project.zoomToFill,
                    backgroundColor: bgColor,
                    borderWidth: borderPx,
                    zoomScale: item.zoomScale
                )
                // Reposition overlay and gesture handling (only when Shift is pressed without Command)
                if isShiftPressed && !isCommandPressed {
                    RepositionOverlayView(
                        item: item,
                        model: model,
                        aspect: model.project.aspect.aspect,
                        zoomToFill: model.project.zoomToFill,
                        isHovered: hoveredItemID == item.id,
                        onHoverChange: { isHovering in
                            hoveredItemID = isHovering ? item.id : nil
                        }
                    )
                }
                // Disabled overlay
                if item.disabled {
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(disabledOverlayOpacity))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .allowsHitTesting(false)
                        Image(systemName: "eye.slash")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double tap - open full view
            fullViewItem = item
            withAnimation(.easeIn(duration: 0.2)) {
                showFullImageView = true
            }
        }
        .onTapGesture(count: 1) {
            // Single tap - toggle disabled (only when not in shift mode)
            if !isShiftPressed {
                toggleDisabled(item)
            }
        }
        .onDrag {
            // Drag to reorder (only when not in shift mode)
            if !isShiftPressed {
                draggingID = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            } else {
                return NSItemProvider() // Empty provider in shift mode
            }
        }
        .onDrop(of: [.text], delegate: DropDelegateImpl(
            overItem: item,
            allItems: $model.project.images,
            draggingID: $draggingID,
            isShiftPressed: isShiftPressed,
            saveToHistory: saveToHistory,  // NEW: Pass the history saving function
            model: model // Pass the AppModel
        ))
    }
}
