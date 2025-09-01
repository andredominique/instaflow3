import SwiftUI
import AppKit

struct RightPreviewPane: View {
    @EnvironmentObject private var model: AppModel

    private let paneWidth: CGFloat = 340
    private let panePadding: CGFloat = 20

    private let phoneCorner: CGFloat = 10
    private let screenPaddingStory: CGFloat = 0
    private let screenPaddingCarousel: CGFloat = 0 // For 4:5 aspect
    
    // Vertical shift settings for different modes
    private let reelVerticalShiftOn: CGFloat = -16    // When toggle is on (Simulate Phone)
    private let reelVerticalShiftOff: CGFloat = -16     // When toggle is off (Actual Export)
    
    private let phoneAspect: CGFloat = 9.0 / 20

    @State private var currentIndex: Int = 0
    @State private var aspectInitialized = false
    @State private var isPlaying = true
    @State private var slideshowSpeed: Double = 1.0
    @State private var slideshowTimer: Timer?
    @State private var useModernRatio: Bool = true // Toggle for 9:17.5 vs 9:16 ratio
    @State private var simulateCarouselUI: Bool = true // Toggle for showing carousel UI elements

    @AppStorage("selectedAppearance") private var selectedAppearance = "light"

    private var slides: [ProjectImage] {
        model.project.images.sorted { $0.orderIndex < $1.orderIndex }.filter { !$0.disabled }
    }
    private var imagesSignature: [String] {
        model.project.images.sorted { $0.orderIndex < $1.orderIndex }.map { "\($0.id.uuidString)|\($0.disabled)|\($0.orderIndex)" }
    }

    private var contentAspect: CGFloat {
        // If it's a reel aspect, use either 9:17.5 or 9:16 based on toggle
        if isReelAspect {
            return useModernRatio ? 9.0 / 17.5 : 9.0 / 16.0
        } else {
            return model.project.aspect.aspect
        }
    }
    
    private var isReelAspect: Bool { model.project.aspect == .story9x16 }
    private var isPostAspect: Bool { abs(model.project.aspect.aspect - (4.0 / 5.0)) < 0.01 }

    private var borderPx: Int {
        if !model.project.cropEnabled { return 0 }
        return isReelAspect ? model.project.reelBorderPx : model.project.carouselBorderPx
    }

    private var borderColor: Color {
        if !model.project.cropEnabled {
            return .clear
        }
        if isReelAspect {
            return model.project.reelBorderColor.swiftUIColor
        } else {
            return model.project.carouselBorderColor.swiftUIColor
        }
    }

    private var screenPaddingCurrent: CGFloat {
        isReelAspect ? screenPaddingStory : screenPaddingCarousel
    }
    
    // Current vertical shift based on toggle state
    private var currentVerticalShift: CGFloat {
        if (!isReelAspect) { return 0 }
        return useModernRatio ? reelVerticalShiftOn : reelVerticalShiftOff
    }
    
    // Show Instagram Reel UI elements based on original toggle
    private var showReelUI: Bool {
        return isReelAspect && useModernRatio
    }
    
    // Show Instagram Carousel UI elements based on new toggle
    private var showCarouselUI: Bool {
        return isPostAspect && simulateCarouselUI
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(Color.adaptiveBackground)
            Divider()
                .background(Color.adaptiveLine)
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: phoneCorner, style: .continuous)
                        .fill(Color.clear)
                        .background(
                            Group {
                                if isReelAspect && showReelUI {
                                    // Show REELBG when Simulate Phone is active for reel
                                    Image("REELBG")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else if isPostAspect && showCarouselUI {
                                    // Show POSTBG when Simulate Phone is active for carousel
                                    Image("POSTBG")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Color.black
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: phoneCorner, style: .continuous))
                        )
                        .overlay(
                            GeometryReader { containerGeo in
                                VStack {
                                    AspectContent(
                                        item: currentItem,
                                        aspect: contentAspect,
                                        cornerRadius: 0,
                                        zoomToFill: model.project.zoomToFill,
                                        borderPx: borderPx * 2,
                                        borderColor: borderColor,
                                        baseWidth: 1080,
                                        cropEnabled: model.project.cropEnabled,
                                        topPadding: screenPaddingCurrent,
                                        forceAspect: true  // Force the aspect ratio to be applied
                                    )
                                    .frame(maxWidth: containerGeo.size.width, maxHeight: containerGeo.size.height)
                                    // Use the computed currentVerticalShift property
                                    .offset(y: currentVerticalShift)
                                }
                            }
                        )
                        // Add Instagram Reel overlay ONLY when appropriate
                        .overlay(
                            Group {
                                if showReelUI {
                                    Image("INSTAREELOVERLAY")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .allowsHitTesting(false) // Make sure it doesn't interfere with interactions
                                }
                            }
                        )
                        .aspectRatio(phoneAspect, contentMode: .fit)
                        // Clip to prevent content from overflowing outside the phone frame
                        .clipShape(RoundedRectangle(cornerRadius: phoneCorner, style: .continuous))
                }
                .frame(height: 600)
                .frame(maxWidth: paneWidth - panePadding * 2)
                .frame(maxWidth: .infinity, alignment: .top)

                HStack(spacing: 8) {
                    Button { prev() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(slides.isEmpty || slides.count <= 1)
                    .padding(.leading, 8)

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

                    Button { next() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(slides.isEmpty || slides.count <= 1)
                    .padding(.trailing, 8)
                }
                .padding(.top, 6)

                Divider()
                    .padding(.vertical, 6)
                
                // Reel aspect toggle with the original functionality
                if isReelAspect {
                    HStack(spacing: 0) {
                        // Left side of toggle: "Actual Export"
                        Text("Actual Export")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 8)
                        
                        // Toggle in the middle with custom blue style
                        Toggle("", isOn: $useModernRatio)
                            .toggleStyle(BlueToggleStyle())
                            .frame(width: 50)
                        
                        // Right side of toggle: "Simulate Phone"
                        Text("Simulate Phone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                    }
                    .padding(.bottom, 6)
                }
                
                // Carousel aspect toggle (new)
                if isPostAspect {
                    HStack(spacing: 0) {
                        // Left side of toggle: "Actual Export"
                        Text("Actual Export")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 8)
                        
                        // Toggle in the middle with custom blue style
                        Toggle("", isOn: $simulateCarouselUI)
                            .toggleStyle(BlueToggleStyle())
                            .frame(width: 50)
                        
                        // Right side of toggle: "Simulate Phone"
                        Text("Simulate Phone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                    }
                    .padding(.bottom, 6)
                }

                HStack(spacing: 4) {
                    Text("Screen Mode:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 0) {
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
            if !isPlaying && !slides.isEmpty && slides.count > 1 {
                startSlideshow()
            }
            applyAppearance()
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
        .frame(height: 70)
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

    private func applyAppearance() {
        let appearance = selectedAppearance == "dark" ? NSAppearance.Name.darkAqua : NSAppearance.Name.aqua
        NSApp.appearance = NSAppearance(named: appearance)
        NotificationCenter.default.post(name: Notification.Name("AppearanceChanged"), object: selectedAppearance)
    }
}

// Custom blue toggle style
struct BlueToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            ZStack {
                // Track (both sides blue)
                Capsule()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 50, height: 24)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 1)
                    .offset(x: configuration.isOn ? 13 : -13)
                    .animation(.spring(response: 0.2), value: configuration.isOn)
                
                // Hit target for toggle
                Color.clear
                    .frame(width: 50, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        configuration.isOn.toggle()
                    }
            }
        }
    }
}

private struct AspectContent: View {
    let item: ProjectImage?
    let aspect: CGFloat
    let cornerRadius: CGFloat
    let zoomToFill: Bool
    let borderPx: Int
    let borderColor: Color
    let baseWidth: CGFloat
    let cropEnabled: Bool
    let topPadding: CGFloat
    let forceAspect: Bool // New parameter to force aspect ratio

    @State private var image: NSImage?
    @State private var imageAspect: CGFloat = 1.0

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
        guard let url = item?.url else {
            image = nil
            imageAspect = 1.0
            return
        }
        if let loadedImage = NSImage(contentsOf: url) {
            image = loadedImage
            imageAspect = loadedImage.size.width / loadedImage.size.height
        } else {
            image = nil
            imageAspect = 1.0
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Border as background, image is padded inside
            ZStack {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(borderColor)
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
                                    .frame(width: innerW - maxPad * 2, height: innerH - maxPad * 2)
                                    .clipped()
                                    .padding(maxPad)
                            }
                            .frame(width: innerW, height: innerH)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .padding(.top, topPadding)
                        } else {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(CGFloat(borderPx) * 1.2)
                                .background(Color.clear)
                                .padding(.top, topPadding)
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
        // Always use the specified aspect ratio when forceAspect is true
        .aspectRatio(cropEnabled || forceAspect ? aspect : (imageAspect > 0 ? imageAspect : 1.0), contentMode: .fit)
        .task { load() }
        .onChange(of: item?.url) { _, _ in load() }
    }
}

private struct ZoomModifier: ViewModifier {
    let zoomToFill: Bool

    func body(content: Content) -> some View {
        if zoomToFill {
            content.scaledToFill()
        } else {
            content.scaledToFit()
        }
    }
}

extension ProjectImage {
    var originalAspect: CGFloat? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return image.size.width / image.size.height
    }
}
