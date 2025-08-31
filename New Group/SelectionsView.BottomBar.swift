//
// Auto-split: bottomMenuBar
//
import SwiftUI
extension SelectionsView {
    var bottomMenuBar: some View {
        ZStack {
            // Semi-transparent black background with rounded corners only for our content
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.5))
            
            // Content layer
            HStack(spacing: 12) {
                // Left side: Undo/Redo buttons with title
                HStack(spacing: 8) {
                    Text("History:")
                        .font(.caption)
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 4) {
                        Button {
                            performUndo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.3))
                        .foregroundStyle(historyManager.canUndo ? .white : .gray)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .disabled(!historyManager.canUndo)
                        .help("Undo (⌘Z)")
                        
                        Button {
                            performRedo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.3))
                        .foregroundStyle(historyManager.canRedo ? .white : .gray)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .disabled(!historyManager.canRedo)
                        .help("Redo (⌘⇧Z)")
                    }
                }
                
                Spacer()
                
                // Center: Image counts
                HStack(spacing: 8) {
                    Text("\(displayItems.count) images")
                        .font(.caption)
                        .foregroundStyle(.white)
                    
                    if enabledImageCount != model.project.images.count {
                        Text("(\(enabledImageCount) enabled)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Right side: Thumbnails controls
                HStack(spacing: 8) {
                    Text("Thumbnails:")
                        .font(.caption)
                        .foregroundStyle(.white)
                    
                    Slider(
                        value: Binding(
                            get: { Double(12 - columns) },
                            set: { columns = 12 - Int($0.rounded()) }
                        ),
                        in: 2...10,
                        step: 1
                    )
                    .frame(width: 100)
                    .tint(Color.white.opacity(0.8))
                    
                    Text("\(columns)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(minWidth: 15)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 44) // Fixed height
    }
}
