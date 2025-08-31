import SwiftUI
import AppKit

struct RightPreviewPane: View {
    @EnvironmentObject private var model: AppModel

    private let paneWidth: CGFloat = 290  // Reduced from 360
    private let panePadding: CGFloat = 12

    private let phoneCorner: CGFloat = 26
    private let screenCorner: CGFloat = 14
    private let screenPadding: CGFloat = 10
    private let phoneAspect: CGFloat = 9.0 / 16.0

    @State private var currentIndex: Int = 0
    @State private var aspectInitialized = false
    
    // Slideshow controls - Changed default to true
    @State private var isPlaying = true
    @State private var slideshowSpeed: Double = 1.0
    // Remove observer from init, will add in .onAppear
    @State private var slideshowTimer: Timer?
    
    // Screen Mode state - Added for appearance toggle
    @AppStorage("selectedAppearance") private var selectedAppearance = "light"

    private var slides: [ProjectImage] {
        model.project.images.sorted { $0.orderIndex < $1.orderIndex }.filter { !$0.disabled }
    }
    private var imagesSignature: [String] {
        model.project.images.sorted { $0.orderIndex < $1.orderIndex }.map { "\($0.id.uuidString)|\($0.disabled)|\($0.orderIndex)" }
    }

    private var contentAspect: CGFloat {
        model.project.cropEnabled ? model.project.aspect.aspect : (currentItem?.originalAspect ?? 1.0)
    }
    private var isReelAspect: Bool { model.project.aspect == .story9x16 }
    
    private var borderPx: Int {
        if !model.project.cropEnabled { return 0 }
        return isReelAspect ? model.project.reelBorderPx : model.project.carouselBorderPx
    }
    
    private var borderColor: Color {
        if !model.project.cropEnabled { return .clear }
        return isReelAspect ? model.project.reelBorderColor.swiftUIColor : model.project.carouselBorderColor.swiftUIColor
    }

    var body: some View {
        VStack(spacing: 0) {
                // NEW: Header matching RootView height
                header
                    .background(Color.adaptiveBackground) // Matches RootView header color
            
            Divider()
                .background(Color.adaptiveLine)
            
            // Main content
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: phoneCorner, style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: screenCorner, style: .continuous)
                                .fill(Color.black)
                                .padding(screenPadding)
                                .overlay {
                                    AspectContent(
                                        item: currentItem,
                                        aspect: contentAspect,
                                        cornerRadius: 0,
                                        zoomToFill: model.project.zoomToFill, // Use global zoom setting
                                        borderPx: borderPx,
                                        borderColor: borderColor,
                                        baseWidth: 1080,
                                        cropEnabled: model.project.cropEnabled
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
                        )
                        .aspectRatio(phoneAspect, contentMode: .fit)
                }
                .frame(height: 450)  // Reduced from 360 to fit narrower pane
                .frame(maxWidth: paneWidth - panePadding * 2)
                .frame(maxWidth: .infinity, alignment: .top)

                // UPDATED: Slideshow controls below preview with navigation buttons
                HStack(spacing: 8) {
                    Button { prev() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(slides.isEmpty || slides.count <= 1)
                    
                    Spacer()
                    
                    Button {
                        toggleSlideshow()
                    } label: {
                        Label(
                            isPlaying ? "Stop" : "Play",
                            systemImage: isPlaying ? "stop.fill" : "play.fill"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(slides.isEmpty || slides.count <= 1)
                    .controlSize(.small)
                    
                    Picker("", selection: $slideshowSpeed) {
                        Text("0.2s").tag(0.2)
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 50)
                    .controlSize(.small)
                    .disabled(slides.isEmpty || slides.count <= 1)
                    
                    Spacer()
                }
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(model.project.caption.isEmpty ? "No caption set." : model.project.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .font(.caption)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
                
                // ADDED: Screen Mode toggle buttons at the bottom
                Divider()
                    .padding(.vertical, 6)
                
                HStack(spacing: 4) {
                    Text("Screen Mode:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        // Light button
                        Button {
                            selectedAppearance = "light"
                            applyAppearance()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sun.max.fill")
                                    .font(.caption2)
                                Text("Light")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selectedAppearance == "light" ?
                            Color.blue :
                            Color(nsColor: .controlBackgroundColor)
                        )
                        .foregroundStyle(selectedAppearance == "light" ? .white : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    selectedAppearance == "light" ?
                                    Color.clear :
                                    Color(nsColor: .separatorColor),
                                    lineWidth: 0.5
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        // Dark button
                        Button {
                            selectedAppearance = "dark"
                            applyAppearance()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "moon.fill")
                                    .font(.caption2)
                                Text("Dark")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selectedAppearance == "dark" ?
                            Color.blue :
                            Color(nsColor: .controlBackgroundColor)
                        )
                        .foregroundStyle(selectedAppearance == "dark" ? .white : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    selectedAppearance == "dark" ?
                                    Color.clear :
                                    Color(nsColor: .separatorColor),
                                    lineWidth: 0.5
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(panePadding)
        }
        .frame(width: paneWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipped()
        .onAppear {
            if !aspectInitialized { aspectInitialized = true }
            clampIndex()
            // Auto-start slideshow if conditions are met
            if !isPlaying && !slides.isEmpty && slides.count > 1 {
                startSlideshow()
            }
            // Apply current appearance
            applyAppearance()

            // Listen for Tap Tempo changes and update slideshowSpeed
            NotificationCenter.default.addObserver(forName: Notification.Name("TapTempoChanged"), object: nil, queue: .main) { notification in
                if let newSpeed = notification.object as? Double {
                    slideshowSpeed = newSpeed
                }
            }
        }
        .onChange(of: imagesSignature) { _, _ in
            clampIndex()
            if isPlaying {
                stopSlideshow()
                // Restart slideshow if conditions are met
                if !slides.isEmpty && slides.count > 1 {
                    startSlideshow()
                }
            }
        }
        .onChange(of: slideshowSpeed) { _, _ in
            if isPlaying {
                stopSlideshow()
                startSlideshow()
            }
        }
        .onDisappear {
            stopSlideshow()
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Spacer()
            Text("Slideshow Preview")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 70) // Match RootView header height
    }

    private var currentItem: ProjectImage? {
        guard slides.indices.contains(currentIndex) else { return nil }
        return slides[currentIndex]
    }
    
    private func clampIndex() {
        if slides.isEmpty { currentIndex = 0 }
        else if currentIndex >= slides.count { currentIndex = max(0, slides.count - 1) }
    }
    
    private func next() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex + 1) % slides.count
    }
    
    private func prev() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex - 1 + slides.count) % slides.count
    }
    
    // MARK: - Slideshow Controls
    
    private func toggleSlideshow() {
        if isPlaying {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }
    
    private func startSlideshow() {
        guard !slides.isEmpty && slides.count > 1 else { return }
        
        isPlaying = true
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowSpeed, repeats: true) { _ in
            next()
        }
    }
    
    private func stopSlideshow() {
        isPlaying = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
    
    // MARK: - Appearance Controls
    
    private func applyAppearance() {
        let appearance = selectedAppearance == "dark" ? NSAppearance.Name.darkAqua : NSAppearance.Name.aqua
        NSApp.appearance = NSAppearance(named: appearance)
        
        // Also notify any listeners about the change
        NotificationCenter.default.post(name: Notification.Name("AppearanceChanged"), object: selectedAppearance)
    }
}

// MARK: - AspectContent with crop toggle support
private struct AspectContent: View {
    let item: ProjectImage?
    let aspect: CGFloat
    let cornerRadius: CGFloat
    let zoomToFill: Bool // Now receives global zoom setting
    let borderPx: Int
    let borderColor: Color
    let baseWidth: CGFloat
    let cropEnabled: Bool

    @State private var image: NSImage?

    private var imageAspect: CGFloat {
        guard let image = image else { return 1.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background color
                borderColor
                Group {
                    if let img = image, let item = item {
                        if cropEnabled {
                            let rawPad = CGFloat(borderPx) / baseWidth * geo.size.width
                            let maxPad = max(0, min(rawPad, min(geo.size.width, geo.size.height) / 2 - 0.5))
                            let innerW = max(0, geo.size.width  - maxPad * 2)
                            let innerH = max(0, geo.size.height - maxPad * 2)
                            GeometryReader { innerGeo in
                                Image(nsImage: img)
                                    .resizable()
                                    .modifier(ZoomModifier(zoomToFill: zoomToFill))
                                    .offset(
                                        x: zoomToFill ? CGFloat(item.offsetX) * maxOffsetX(for: CGSize(width: innerW, height: innerH)) : 0,
                                        y: zoomToFill ? CGFloat(item.offsetY) * maxOffsetY(for: CGSize(width: innerW, height: innerH)) : 0
                                    )
                                    .frame(width: innerW, height: innerH)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(borderColor, lineWidth: CGFloat(borderPx) * 1.2)
                                    )
                            }
                            .frame(width: innerW, height: innerH)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        } else {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(borderColor, lineWidth: CGFloat(borderPx) * 1.2)
                                )
                        }
                    } else if item != nil {
                        Color.gray.opacity(0.15).overlay(ProgressView())
                    } else {
                        Color.gray.opacity(0.08).overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                Text("No images")
                            }
                            .foregroundStyle(.secondary)
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(cropEnabled ? aspect : (imageAspect > 0 ? imageAspect : 1.0), contentMode: .fit)
        .task { load() }
        .onChange(of: item?.url) { _, _ in load() }
    }

    // Offset calculations for cropped mode
    private func maxOffsetX(for containerSize: CGSize) -> CGFloat {
        guard cropEnabled && zoomToFill else { return 0 }
        if imageAspect > aspect {
            let imageWidth = containerSize.height * imageAspect
            let overflow = imageWidth - containerSize.width
            return overflow / 2
        }
        return 0
    }
    
    private func maxOffsetY(for containerSize: CGSize) -> CGFloat {
        guard cropEnabled && zoomToFill else { return 0 }
        if imageAspect < aspect {
            let imageHeight = containerSize.width / imageAspect
            let overflow = imageHeight - containerSize.height
            return overflow / 2
        }
        return 0
    }

    private func load() {
        guard let url = item?.url else { image = nil; return }
        image = NSImage(contentsOf: url)
    }
}

private struct ZoomModifier: ViewModifier {
    let zoomToFill: Bool
    func body(content: Content) -> some View {
        zoomToFill ? AnyView(content.scaledToFill()) : AnyView(content.scaledToFit())
    }
}

// Extension to get original image aspect ratio
extension ProjectImage {
    var originalAspect: CGFloat? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return image.size.width / image.size.height
    }
}
