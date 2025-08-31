import SwiftUI
import AppKit

struct CarouselPreview: View {
    @EnvironmentObject private var model: AppModel

    private var ratio: CGFloat { model.project.aspect.aspect } // width/height
    private var items: [ProjectImage] {
        model.project.images
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { !$0.disabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Text(model.project.aspect.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        Thumb(item: item, ratio: ratio)
                            .frame(height: 260)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct Thumb: View {
    let item: ProjectImage
    let ratio: CGFloat
    @State private var img: NSImage?

    private var imageAspect: CGFloat {
        guard let img = img else { return 1.0 }
        return img.size.width / img.size.height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let ns = img {
                    Image(nsImage: ns)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .offset(
                            x: CGFloat(item.offsetX) * maxOffsetX(for: proxy.size),
                            y: CGFloat(item.offsetY) * maxOffsetY(for: proxy.size)
                        )
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .overlay(ProgressView())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(radius: 1)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .task {
            if img == nil, let ns = NSImage(contentsOf: item.url) {
                img = ns
            }
        }
    }
    
    // CONSISTENT offset calculations - same as SelectionsView
    private func maxOffsetX(for containerSize: CGSize) -> CGFloat {
        if imageAspect > ratio {
            let imageWidth = containerSize.height * imageAspect
            let overflow = imageWidth - containerSize.width
            return overflow / 2
        }
        return 0
    }
    
    private func maxOffsetY(for containerSize: CGSize) -> CGFloat {
        if imageAspect < ratio {
            let imageHeight = containerSize.width / imageAspect
            let overflow = imageHeight - containerSize.height
            return overflow / 2
        }
        return 0
    }
}
