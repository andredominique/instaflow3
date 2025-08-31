import SwiftUI
import AppKit

// Keep timing frame-accurate in the rendered reel
@inline(__always)
func snapToFrameDuration(_ seconds: Double, fps: Int) -> Double {
    let frames = max(1, Int((seconds * Double(fps)).rounded()))
    return Double(frames) / Double(fps)
}

struct FinalPreviewView: View {
    @EnvironmentObject private var model: AppModel

    // MARK: - UI state
    @State private var isExporting = false
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var openInFinderURL: URL? = nil

    // Persisted output dir
    @State private var lastOutputDir: URL? = nil
    private let defaultsKeyLastExportPath = "InstaFlow.lastExportPath"

    // Hold last exported media for drag-and-drop
    @State private var lastExportedMedia: [URL] = []

    // Toggle to reveal WhatsApp UI
    @State private var showWhatsAppPanel: Bool = false

    // One-time init for defaults (caption off)
    @State private var didInitDefaults: Bool = false

    // Fixed reel (video) settings
    private let reelFPS: Int = 25
    private let reelSize = CGSize(width: 1080, height: 1920) // portrait

    // Convenience
    private var enabledImagesOrdered: [ProjectImage] {
        model.project.images.sorted { $0.orderIndex < $1.orderIndex }.filter { !$0.disabled }
    }

    // Helpers: ColorData → SwiftUI Color
    private var reelBGColor: Color { model.project.reelBorderColor.swiftUIColor }
    private var carouselBGColor: Color { model.project.carouselBorderColor.swiftUIColor }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {

                // Top title
                HStack {
                    Text("Slideshow Pace").font(.title3).bold()
                    Spacer()
                }
                .padding(.top, 6)

                // Show settings only when crop is enabled
                if model.project.cropEnabled {
                    // Reel settings (Tap Tempo embedded)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            // Tap Tempo (writes to model.project.reelSecondsPerImage)
                            TapTempoControl(embedded: true, hideHeader: true, showReset: false)
                                .environmentObject(model)
                                .environment(\.font, .body)
                        }
                        .controlSize(.small)
                    }
                    .onChange(of: model.project.reelSecondsPerImage) { _, newVal in
                        // Clamp + snap, regardless of whether value came from Tap Tempo or elsewhere
                        let clamped = min(max(newVal, 0.1), 10.0)
                        let snapped = snapToFrameDuration(clamped, fps: reelFPS)
                        if snapped != model.project.reelSecondsPerImage {
                            model.project.reelSecondsPerImage = snapped
                        }
                        // Notify RightPreviewPane to update slideshow speed
                        NotificationCenter.default.post(name: Notification.Name("TapTempoChanged"), object: snapped)
                    }
                } else {
                    // Show message when crop is disabled
                    GroupBox {
                        VStack(spacing: 16) {
                            Image(systemName: "crop.rotate")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            
                            Text("Crop Mode Disabled")
                                .font(.headline)
                            
                            Text("Export settings are only available when crop mode is enabled. Enable crop mode in the Preview pane to access aspect ratio settings, borders, and zoom options.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                    }
                }

                // —— Export section: Output location + caption settings + buttons ——
                HStack {
                    Text("Export").font(.title3).bold()
                    Spacer()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        // Output location row
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Output location").font(.headline)
                                Text(model.project.outputPath?.path(percentEncoded: false) ?? "Not set")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button { pickOutputFolder() } label: {
                                Label(model.project.outputPath == nil ? "Choose…" : "Change…", systemImage: "folder")
                            }
                        }

                        // Caption settings
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Caption Settings").font(.headline)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.project.caption, forType: .string)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }

                            Toggle("Save as .txt file", isOn: $model.project.saveCaptionTxt)
                                .toggleStyle(.switch)
                                .font(.body)
                                .help("When exporting, also write caption.txt into the output folder.")
                        }

                        // Export buttons - simplified (removed square, kept carousel and reel)
                        HStack(spacing: 10) {
                            if model.project.cropEnabled {
                                Button { Task { await runExport(square: false, carousel: true, reel: false) } } label: {
                                    Label("Export Carousel", systemImage: "square.grid.2x2")
                                }
                                .disabled(isExporting || model.project.outputPath == nil || enabledImagesOrdered.isEmpty)

                                Button { Task { await runExport(square: false, carousel: false, reel: true) } } label: {
                                    Label("Export Reel", systemImage: "film")
                                }
                                .disabled(isExporting || model.project.outputPath == nil || enabledImagesOrdered.isEmpty)

                                Button { Task { await runExport(square: false, carousel: true, reel: true) } } label: {
                                    Label("Export All", systemImage: "square.grid.2x2.fill")
                                }
                                .disabled(isExporting || model.project.outputPath == nil || enabledImagesOrdered.isEmpty)
                            } else {
                                Button { Task { await runExport(square: false, carousel: false, reel: false) } } label: {
                                    Label("Export Original Images", systemImage: "photo.on.rectangle.angled")
                                }
                                .disabled(isExporting || model.project.outputPath == nil || enabledImagesOrdered.isEmpty)
                            }

                            Spacer()

                            // Open in Finder (if available)
                            if let openURL = openInFinderURL {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([openURL])
                                } label: {
                                    Label("Open in Finder", systemImage: "folder.fill")
                                }
                            }

                            // Send to WhatsApp
                            Button {
                                if lastExportedMedia.isEmpty {
                                    statusMessage = "Export something first, then you can send to WhatsApp."
                                    showWhatsAppPanel = false
                                } else {
                                    showWhatsAppPanel = true
                                }
                            } label: {
                                Label("Send to WhatsApp", systemImage: "paperplane")
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                }

                // Progress + status
                if isExporting {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress).progressViewStyle(.linear)
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } else if !statusMessage.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                // WhatsApp panel
                if showWhatsAppPanel, !lastExportedMedia.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Send to WhatsApp").font(.headline)
                                Spacer()
                                Button {
                                    showWhatsAppPanel = false
                                } label: {
                                    Label("Hide", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }

                            // Media drag box
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1) Drag media files").font(.body).bold()
                                Text("Open a chat in WhatsApp, then drag this box onto the conversation to attach all items.")
                                    .font(.caption).foregroundStyle(.secondary)

                                DragMediaBox(urls: lastExportedMedia)
                                    .frame(height: 74)
                            }

                            Divider()

                            // Caption drag box
                            VStack(alignment: .leading, spacing: 6) {
                                Text("2) Drag caption").font(.body).bold()
                                Text("Now drag the caption to the message field.")
                                    .font(.caption).foregroundStyle(.secondary)

                                DragCaptionBox(caption: model.project.caption.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .frame(height: 60)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // restore last output path if project doesn't have one
            if model.project.outputPath == nil {
                if let saved = UserDefaults.standard.string(forKey: defaultsKeyLastExportPath) {
                    let url = URL(fileURLWithPath: saved)
                    if FileManager.default.fileExists(atPath: url.path) {
                        model.project.outputPath = url
                    }
                }
            }
            if let out = model.project.outputPath { lastOutputDir = out }

            // Default Caption Settings to OFF on first entry
            if !didInitDefaults {
                didInitDefaults = true
                if model.project.saveCaptionTxt {
                    model.project.saveCaptionTxt = false
                }
            }
        }
    }

    // MARK: - Actions

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.urls.first {
            model.project.outputPath = url
            lastOutputDir = url
            statusMessage = "Output folder set."
            openInFinderURL = url
            UserDefaults.standard.set(url.path(percentEncoded: false), forKey: defaultsKeyLastExportPath)
        }
    }

    private func subdirName() -> String {
        let ref = model.project.referenceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if ref.isEmpty {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return "Export_\(df.string(from: Date()))"
        }
        return ref
    }

    private func runExport(square: Bool, carousel: Bool, reel: Bool) async {
        guard model.project.outputPath != nil else {
            statusMessage = "Set an output folder first."
            return
        }
        guard !enabledImagesOrdered.isEmpty else {
            statusMessage = "No enabled images to export."
            return
        }

        isExporting = true
        progress = 0
        statusMessage = "Exporting…"
        openInFinderURL = nil
        lastExportedMedia = []
        showWhatsAppPanel = false

        do {
            let refName = subdirName()
            let outDir = model.project.outputPath!.appendingPathComponent(refName, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            var totalSteps = 0
            if square { totalSteps += 1 }
            if carousel { totalSteps += 1 }
            if reel { totalSteps += 1 }
            // If no crop mode, just copy original images
            if !model.project.cropEnabled && !square && !carousel && !reel { totalSteps = 1 }
            
            var step = 0
            var exportedURLs: [URL] = []

            if model.project.cropEnabled {
                // Export square images (keep for backwards compatibility, but not exposed in UI)
                if square {
                    await MainActor.run { statusMessage = "Exporting square images…" }
                    let squareOut = outDir.appendingPathComponent("Square", isDirectory: true)
                    try FileManager.default.createDirectory(at: squareOut, withIntermediateDirectories: true)

                    let urls = try ImageProcessor.exportSquareImages(
                        enabledImagesOrdered,
                        outputDir: squareOut,
                        borderPx: model.project.squareBorderPx,
                        zoomToFill: model.project.zoomToFill, // Use global zoom setting
                        background: NSColor(
                            srgbRed: model.project.squareBorderColor.red,
                            green: model.project.squareBorderColor.green,
                            blue: model.project.squareBorderColor.blue,
                            alpha: 1
                        )
                    )
                    exportedURLs.append(contentsOf: urls)

                    step += 1
                    await MainActor.run { progress = Double(step) / Double(max(totalSteps, 1)) }
                }

                // Export carousel images
                if carousel {
                    await MainActor.run { statusMessage = "Exporting carousel images…" }
                    let imageOut = outDir.appendingPathComponent("Images", isDirectory: true)
                    try FileManager.default.createDirectory(at: imageOut, withIntermediateDirectories: true)

                    let urls = try ImageProcessor.exportCarouselImages(
                        enabledImagesOrdered,
                        outputDir: imageOut,
                        borderPx: model.project.carouselBorderPx,
                        zoomToFill: model.project.zoomToFill, // Use global zoom setting
                        background: NSColor(
                            srgbRed: model.project.carouselBorderColor.red,
                            green: model.project.carouselBorderColor.green,
                            blue: model.project.carouselBorderColor.blue,
                            alpha: 1
                        )
                    )
                    exportedURLs.append(contentsOf: urls)

                    step += 1
                    await MainActor.run { progress = Double(step) / Double(max(totalSteps, 1)) }
                }

                // Export reel (video)
                if reel {
                    await MainActor.run { statusMessage = "Rendering reel video…" }
                    let reelOut = outDir.appendingPathComponent("Reel.mp4")

                    // Use snapped, frame-accurate value
                    let snappedSPI = snapToFrameDuration(model.project.reelSecondsPerImage, fps: reelFPS)

                    try ImageProcessor.makeReelMP4HighQuality(
                        from: enabledImagesOrdered,
                        secondsPerImage: snappedSPI,
                        fps: reelFPS,
                        targetSize: reelSize,
                        outputURL: reelOut,
                        bitrate: 16_000_000,
                        useHEVC: false,
                        borderPx: model.project.reelBorderPx,
                        zoomToFill: model.project.zoomToFill, // Use global zoom setting
                        background: NSColor(
                            srgbRed: model.project.reelBorderColor.red,
                            green: model.project.reelBorderColor.green,
                            blue: model.project.reelBorderColor.blue,
                            alpha: 1
                        )
                    )
                    exportedURLs.append(reelOut)

                    step += 1
                    await MainActor.run { progress = Double(step) / Double(max(totalSteps, 1)) }
                }

                // Write caption.txt if requested and caption is not empty
                if model.project.saveCaptionTxt && !model.project.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let captionURL = outDir.appendingPathComponent("caption.txt")
                    let text = model.project.caption
                    try? text.data(using: .utf8)?.write(to: captionURL, options: .atomic)
                }
            } else {
                // Export original images (no cropping)
                await MainActor.run { statusMessage = "Copying original images…" }
                let originalOut = outDir.appendingPathComponent("Original", isDirectory: true)
                try FileManager.default.createDirectory(at: originalOut, withIntermediateDirectories: true)
                
                for (index, image) in enabledImagesOrdered.enumerated() {
                    let fileName = String(format: "image_%03d", index + 1) + "." + image.url.pathExtension
                    let destURL = originalOut.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: image.url, to: destURL)
                    exportedURLs.append(destURL)
                }
                
                if model.project.saveCaptionTxt && !model.project.caption.isEmpty {
                    let captionURL = originalOut.appendingPathComponent("caption.txt")
                    let text = model.project.caption
                    try text.data(using: .utf8)?.write(to: captionURL, options: .atomic)
                }
                
                step = 1
                await MainActor.run { progress = 1.0 }
            }

            let media = exportedURLs.filter(isShareableByWhatsApp)
            await MainActor.run {
                statusMessage = "Done → \(outDir.path(percentEncoded: false))"
                openInFinderURL = outDir
                lastExportedMedia = media
            }
        } catch {
            await MainActor.run {
                statusMessage = "Export failed: \(error.localizedDescription)"
                lastExportedMedia = []
            }
        }

        isExporting = false
    }

    // Shareable types (WhatsApp accepts these)
    private func isShareableByWhatsApp(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg","jpeg","png","heic","webp","mp4","mov"].contains(ext)
    }
}

// MARK: - Drag-to-WhatsApp: MEDIA box

private struct DragMediaBox: View {
    let urls: [URL]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )

            VStack(spacing: 6) {
                Label("Drag \(urls.count) media item\(urls.count == 1 ? "" : "s")",
                      systemImage: "square.and.arrow.up.on.square")
                    .font(.subheadline)
                    .bold()
                Text("Drop onto the open WhatsApp conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .overlay(DragFilesSourceView(urls: urls).allowsHitTesting(true))
        .accessibilityLabel("Drag media to WhatsApp")
    }
}

private struct DragFilesSourceView: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> DragFilesNSView {
        let v = DragFilesNSView()
        v.urls = urls
        return v
    }

    func updateNSView(_ nsView: DragFilesNSView, context: Context) {
        nsView.urls = urls
        nsView.needsDisplay = true
    }
}

private final class DragFilesNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !urls.isEmpty else { return }
        let items: [NSDraggingItem] = urls.enumerated().map { (idx, url) in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let frame = NSRect(x: 0, y: 0, width: 220, height: 28)
            draggingItem.setDraggingFrame(frame, contents: dragBadge(label: "Media \(idx + 1)"))
            return draggingItem
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    private func dragBadge(label: String) -> NSImage {
        let size = NSSize(width: 220, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        (label as NSString).draw(in: rect.insetBy(dx: 8, dy: 6), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

// MARK: - Drag-to-WhatsApp: CAPTION box

private struct DragCaptionBox: View {
    let caption: String

    var body: some View {
        let isEmpty = caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let borderColor: Color = isEmpty
            ? Color(nsColor: .quaternaryLabelColor)
            : Color.blue.opacity(0.25)

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )

            VStack(spacing: 6) {
                Label(isEmpty ? "No caption to drag" : "Drag caption text",
                      systemImage: "text.justify")
                    .font(.subheadline)
                    .bold()
                Text(isEmpty ? "Set a caption first." : "Drop onto the WhatsApp message field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .overlay(DragTextSourceView(text: caption).allowsHitTesting(true))
        .accessibilityLabel("Drag caption to WhatsApp")
    }
}

private struct DragTextSourceView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> DragTextNSView {
        let v = DragTextNSView()
        v.text = text
        return v
    }
    func updateNSView(_ nsView: DragTextNSView, context: Context) {
        nsView.text = text
        nsView.needsDisplay = true
    }
}

private final class DragTextNSView: NSView, NSDraggingSource {
    var text: String = ""
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let pbItem = NSPasteboardItem()
        pbItem.setString(trimmed, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        let frame = NSRect(x: 0, y: 0, width: 220, height: 28)
        draggingItem.setDraggingFrame(frame, contents: dragBadge(label: "Caption"))

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func dragBadge(label: String) -> NSImage {
        let size = NSSize(width: 220, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        (label as NSString).draw(in: rect.insetBy(dx: 8, dy: 6), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
