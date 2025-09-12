// NOTE: This is a new version with fixed offset calculations
import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import UniformTypeIdentifiers
import ImageIO

struct ImageProcessor {
    // Helper functions for size calculations
    private static func aspectFitSize(source: CGSize, into target: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = min(target.width / source.width, target.height / source.height)
        return CGSize(width: floor(source.width * scale), height: floor(source.height * scale))
    }

    private static func aspectFillSize(source: CGSize, into target: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = max(target.width / source.width, target.height / source.height)
        return CGSize(width: floor(source.width * scale), height: floor(source.height * scale))
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary) {
            return cg
        }
        guard let nsimg = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: nsimg.size)
        return nsimg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // Main export function for carousel images
    static func exportCarouselImages(_ images: [ProjectImage],
                                   outputDir: URL,
                                   borderPx: Int = 0,
                                   zoomToFill: Bool = false,
                                   background: NSColor = .white) throws -> [URL] {
        
        let finalWidth: CGFloat = 1080
        let finalHeight: CGFloat = 1350
        let canvasSize = CGSize(width: finalWidth, height: finalHeight)
        var written: [URL] = []
        
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let bg = (background.usingColorSpace(.sRGB) ?? background)
        let doubleBorderPx = borderPx * 2
        
        for (idx, item) in images.enumerated() {
            print("Debug: Processing image \(idx+1) with offset: (\(item.offsetX), \(item.offsetY))")
            
            autoreleasepool {
                guard let cg = loadCGImage(url: item.url) else { return }
                
                guard let ctx = CGContext(
                    data: nil,
                    width: Int(canvasSize.width),
                    height: Int(canvasSize.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                
                // Fill background
                ctx.setFillColor(bg.cgColor)
                ctx.fill(CGRect(origin: .zero, size: canvasSize))
                
                let borderWidth = CGFloat(doubleBorderPx)
                let contentRect = CGRect(
                    x: borderWidth,
                    y: borderWidth,
                    width: canvasSize.width - borderWidth * 2,
                    height: canvasSize.height - borderWidth * 2
                )
                
                let srcSize = CGSize(width: cg.width, height: cg.height)
                let scaled = zoomToFill
                    ? aspectFillSize(source: srcSize, into: contentRect.size)
                    : aspectFitSize(source: srcSize, into: contentRect.size)
                
                // Center the image
                var drawRect = CGRect(
                    x: contentRect.midX - scaled.width / 2,
                    y: contentRect.midY - scaled.height / 2,
                    width: scaled.width,
                    height: scaled.height
                )
                
                // Calculate maximum possible offsets
                let imageAspect = srcSize.width / srcSize.height
                let containerAspect = contentRect.width / contentRect.height
                
                var maxOffsetX: CGFloat = 0
                var maxOffsetY: CGFloat = 0
                
                if imageAspect > containerAspect {
                    let imageWidth = contentRect.height * imageAspect
                    maxOffsetX = (imageWidth - contentRect.width) / 2
                }
                
                if imageAspect < containerAspect {
                    let imageHeight = contentRect.width / imageAspect
                    maxOffsetY = (imageHeight - contentRect.height) / 2
                }
                
                print("Debug: maxOffsets: (\(maxOffsetX), \(maxOffsetY))")
                
                // Apply offsets with inversion to match UI movement
                if maxOffsetX > 0 || maxOffsetY > 0 {
                    drawRect.origin.x += CGFloat(-item.offsetX) * maxOffsetX
                    drawRect.origin.y += CGFloat(-item.offsetY) * maxOffsetY
                }
                
                print("Debug: final drawRect: \(drawRect)")
                
                // Draw with clipping
                ctx.saveGState()
                ctx.clip(to: contentRect)
                ctx.draw(cg, in: drawRect)
                ctx.restoreGState()
                
                // Write the image
                guard let outCG = ctx.makeImage() else { return }
                let outURL = outputDir.appendingPathComponent(String(format: "image_%03d.jpg", idx + 1))
                do {
                    try writeJPEG(outCG, to: outURL)
                    written.append(outURL)
                } catch {
                    print("Error writing image \(idx+1): \(error)")
                }
            }
        }
        
        return written
    }
    
    // Main export function for reel video
    static func makeReelMP4HighQuality(from images: [ProjectImage],
                                     secondsPerImage: Double,
                                     fps: Int,
                                     targetSize: CGSize,
                                     outputURL: URL,
                                     bitrate: Int = 16_000_000,
                                     useHEVC: Bool = false,
                                     borderPx: Int = 0,
                                     zoomToFill: Bool = false,
                                     background: NSColor = .white) throws {
        
        try? FileManager.default.removeItem(at: outputURL)
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let codec: AVVideoCodecType = useHEVC ? .hevc : .h264
        
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps
        ]
        compression[AVVideoProfileLevelKey] = useHEVC ? "HEVC_Main_AutoLevel" : "H264_High_AutoLevel"
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                          sourcePixelBufferAttributes: adaptorAttrs)
        
        guard writer.canAdd(input) else {
            throw NSError(domain: "ImageProcessor", code: -10,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot add input to writer"])
        }
        writer.add(input)
        
        guard writer.startWriting() else {
            throw NSError(domain: "ImageProcessor", code: -11,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let framesPerImage = max(1, Int(round(Double(fps) * secondsPerImage)))
        var currentTime = CMTime.zero
        
        writer.startSession(atSourceTime: .zero)
        
        let reelBorderPx = Int(Double(borderPx) * 3.0)
        
        for (idx, item) in images.enumerated() {
            print("Debug: Processing reel frame \(idx+1) with offset: (\(item.offsetX), \(item.offsetY))")
            
            autoreleasepool {
                guard let cg = loadCGImage(url: item.url),
                      let pixelBuffer = makeReelFrame(from: cg,
                                                    item: item,
                                                    size: targetSize,
                                                    borderPx: reelBorderPx,
                                                    zoomToFill: zoomToFill,
                                                    background: background) else { return }
                
                for _ in 0..<framesPerImage {
                    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
                    adaptor.append(pixelBuffer, withPresentationTime: currentTime)
                    currentTime = currentTime + frameDuration
                }
            }
        }
        
        input.markAsFinished()
        
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        
        if writer.status != .completed {
            throw NSError(domain: "ImageProcessor", code: -12,
                        userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "Failed to finalize video"])
        }
    }
    
    // Helpers
    private static func writeJPEG(_ cg: CGImage, to url: URL) throws {
        let type = UTType.jpeg.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw NSError(domain: "ImageProcessor", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }
        let props = [kCGImageDestinationLossyCompressionQuality as String: 0.95] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        if !CGImageDestinationFinalize(dest) {
            throw NSError(domain: "ImageProcessor", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to write JPEG"])
        }
    }
    
    private static func makeReelFrame(from cg: CGImage,
                                    item: ProjectImage,
                                    size: CGSize,
                                    borderPx: Int,
                                    zoomToFill: Bool,
                                    background: NSColor) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(size.width),
                                       Int(size.height),
                                       kCVPixelFormatType_32BGRA,
                                       attrs as CFDictionary,
                                       &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let ctx = CGContext(data: base,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: bitmapInfo)
        else { return nil }
        
        let bg = (background.usingColorSpace(.sRGB) ?? background)
        ctx.setFillColor(bg.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        let borderWidth = CGFloat(borderPx)
        let contentRect = CGRect(
            x: borderWidth,
            y: borderWidth,
            width: size.width - borderWidth * 2,
            height: size.height - borderWidth * 2
        )
        
        let srcSize = CGSize(width: cg.width, height: cg.height)
        let scaled = zoomToFill
            ? aspectFillSize(source: srcSize, into: contentRect.size)
            : aspectFitSize(source: srcSize, into: contentRect.size)
        
        var drawRect = CGRect(
            x: contentRect.midX - scaled.width / 2,
            y: contentRect.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        )
        
        // Calculate offsets
        let imageAspect = srcSize.width / srcSize.height
        let containerAspect = contentRect.width / contentRect.height
        
        var maxOffsetX: CGFloat = 0
        var maxOffsetY: CGFloat = 0
        
        if imageAspect > containerAspect {
            let imageWidth = contentRect.height * imageAspect
            maxOffsetX = (imageWidth - contentRect.width) / 2
        }
        
        if imageAspect < containerAspect {
            let imageHeight = contentRect.width / imageAspect
            maxOffsetY = (imageHeight - contentRect.height) / 2
        }
        
        // Apply offsets with inversion
        if maxOffsetX > 0 || maxOffsetY > 0 {
            drawRect.origin.x += CGFloat(-item.offsetX) * maxOffsetX
            drawRect.origin.y += CGFloat(-item.offsetY) * maxOffsetY
        }
        
        print("Debug: Reel frame: maxOffsets=(\(maxOffsetX), \(maxOffsetY)), finalRect=\(drawRect)")
        
        // Draw with clipping
        ctx.saveGState()
        ctx.clip(to: contentRect)
        ctx.draw(cg, in: drawRect)
        ctx.restoreGState()
        
        return pixelBuffer
    }
}