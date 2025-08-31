import SwiftUI
import AppKit

struct DragRepositionSheet: View {
    let item: ProjectImage
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var offsetX: Double
    @State private var offsetY: Double
    @State private var isDragging = false
    
    init(item: ProjectImage, model: AppModel) {
        self.item = item
        self.model = model
        self._offsetX = State(initialValue: item.offsetX)
        self._offsetY = State(initialValue: item.offsetY)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Reposition Image")
                .font(.title2)
                .bold()
            
            VStack(spacing: 16) {
                Text("Click and drag the image to reposition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                DraggableImageViewOld(
                    url: item.url,
                    aspect: model.project.aspect.aspect,
                    offsetX: $offsetX,
                    offsetY: $offsetY,
                    isDragging: $isDragging,
                    zoomToFill: model.project.zoomToFill
                )
                .frame(width: previewWidth, height: previewHeight)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isDragging ? Color.blue : Color.clear, lineWidth: 3)
                )
                
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("Horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", offsetX))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    VStack(spacing: 4) {
                        Text("Vertical")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", offsetY))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            HStack(spacing: 16) {
                Button("Reset") {
                    withAnimation(.easeOut(duration: 0.3)) {
                        offsetX = 0.0
                        offsetY = 0.0
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Apply") {
                    model.setCropOffset(for: item.id, offsetX: offsetX, offsetY: offsetY)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private var previewWidth: CGFloat {
        switch model.project.aspect {
        case .feed4x5: return 320
        case .story9x16: return 270
        case .square1x1: return 320
        }
    }
    
    private var previewHeight: CGFloat {
        previewWidth / model.project.aspect.aspect
    }
}