//
// Auto-split: thumbnails
//
import SwiftUI
extension SelectionsView {
var thumbnails: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: .init(.flexible(), spacing: 10), count: columns),
                spacing: 10
            ) {
                ForEach(displayItems, id: \.id) { item in
                    thumbnailItem(item, isOptionPressed: isOptionPressed, isShiftPressed: isShiftPressed)
                }
            }
            .padding(12)
        }
    }
}
