//
//  ImageProcessor.swift
//  InstaFlow
//
//  Full version — carousel export + reel export + square export
//

import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import UniformTypeIdentifiers
import ImageIO

struct ImageProcessor {

    // MARK: - Square export (1:1) ------------------------------------------

    /// Exports images to 1080×1080 (1:1) JPEGs with optional border (px), zoom-to-fill,
    /// and a background color (used for the border/mat).
    static func exportSquareImages(_ images: [ProjectImage],
                                   outputDir: URL,
                                   borderPx: Int = 0,
                                   zoomToFill: Bool = false,
                                   background: NSColor = .white) throws -> [URL] {

        let canvasSize = CGSize(width: 1080, height: 1080) // 1:1 square
        var written: [URL] = []

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Convert background to sRGB for consistency
        let bg = (background.usingColorSpace(.sRGB) ?? background)
        
        // Double the border width as requested
        let doubleBorderPx = borderPx * 2

        for (idx, item) in images.enumerated() {
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

                // Fill the entire canvas with the border/background color
                ctx.setFillColor(bg.cgColor)
                ctx.fill(CGRect(origin: .zero, size: canvasSize))
                
                let borderWidth = CGFloat(doubleBorderPx)
                
                if borderWidth > 0 {
                    // Define the content area with the border inset
                    let contentRect = CGRect(
                        x: borderWidth,
                        y: borderWidth,
                        width: canvasSize.width - borderWidth * 2,
                        height: canvasSize.height - borderWidth * 2
                    )
                    
                    // Compute scaled image size
                    let srcSize = CGSize(width: cg.width, height: cg.height)
                    let scaled = zoomToFill
                        ? aspectFillSize(source: srcSize, into: contentRect.size)
                        : aspectFitSize(source: srcSize, into: contentRect.size)
                    
                    // Center the image in the content rect
                    var drawRect = CGRect(
                        x: contentRect.midX - scaled.width / 2,
                        y: contentRect.midY - scaled.height / 2,
                        width: scaled.width,
                        height: scaled.height
                    )
                    
                    // Apply repositioning offset
                    let imageAspect = srcSize.width / srcSize.height
                    let containerAspect = contentRect.width / contentRect.height
                    
                    // Calculate max offsets
                    let maxOffsetX: CGFloat
                    if imageAspect > containerAspect {
                        let imageWidth = contentRect.height * imageAspect
                        let overflow = imageWidth - contentRect.width
                        maxOffsetX = overflow / 2
                    } else {
                        maxOffsetX = 0
                    }
                    
                    let maxOffsetY: CGFloat
                    if imageAspect < containerAspect {
                        let imageHeight = contentRect.width / imageAspect
                        let overflow = imageHeight - contentRect.height
                        maxOffsetY = overflow / 2
                    } else {
                        maxOffsetY = 0
                    }
                    
                    // Apply the offsets
                    let offsetX = CGFloat(item.offsetX) * maxOffsetX
                    let offsetY = CGFloat(item.offsetY) * maxOffsetY
                    drawRect.origin.x += offsetX
                    drawRect.origin.y += offsetY
                    
                    // Draw the image with clipping to content rect
                    ctx.saveGState()
                    ctx.clip(to: contentRect)
                    ctx.draw(cg, in: drawRect)
                    ctx.restoreGState()
                } else {
                    // No border case - just draw the image fitted to the canvas
                    let srcSize = CGSize(width: cg.width, height: cg.height)
                    let scaled = zoomToFill
                        ? aspectFillSize(source: srcSize, into: canvasSize)
                        : aspectFitSize(source: srcSize, into: canvasSize)
                    
                    let drawRect = CGRect(
                        x: (canvasSize.width - scaled.width) / 2,
                        y: (canvasSize.height - scaled.height) / 2,
                        width: scaled.width,
                        height: scaled.height
                    )
                    
                    ctx.draw(cg, in: drawRect)
                }

                guard let outCG = ctx.makeImage() else { return }
                let outURL = outputDir.appendingPathComponent(String(format: "image_%03d.jpg", idx + 1))
                do {
                    try writeJPEG(outCG, to: outURL, quality: 0.95)
                    written.append(outURL)
                } catch {
                    // skip this image and continue
                }
            }
        }

        return written
    }

    // MARK: - Carousel export (4:5) ------------------------------------------

    /// Exports images to 1080×1350 (4:5) JPEGs with optional border (px), zoom-to-fill,
    /// and a background color (used for the border/mat).
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
        
        // Convert background to sRGB for consistency - same as square export
        let bg = (background.usingColorSpace(.sRGB) ?? background)
        
        // Double the border width as requested
        let doubleBorderPx = borderPx * 2
        
        for (idx, item) in images.enumerated() {
            autoreleasepool {
                guard let cg = loadCGImage(url: item.url) else { return }
                
                // Create context with explicit sRGB color space - same as square export
                guard let ctx = CGContext(
                    data: nil,
                    width: Int(canvasSize.width),
                    height: Int(canvasSize.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                
                // Fill the entire canvas with the border/background color
                ctx.setFillColor(bg.cgColor)
                ctx.fill(CGRect(origin: .zero, size: canvasSize))
                
                let borderWidth = CGFloat(doubleBorderPx)
                
                if borderWidth > 0 {
                    // Define the content area with the border inset
                    let contentRect = CGRect(
                        x: borderWidth,
                        y: borderWidth,
                        width: canvasSize.width - borderWidth * 2,
                        height: canvasSize.height - borderWidth * 2
                    )
                    
                    // Compute scaled image size
                    let srcSize = CGSize(width: cg.width, height: cg.height)
                    let scaled = zoomToFill
                        ? aspectFillSize(source: srcSize, into: contentRect.size)
                        : aspectFitSize(source: srcSize, into: contentRect.size)
                    
                    // Center the image in the content rect
                    var drawRect = CGRect(
                        x: contentRect.midX - scaled.width / 2,
                        y: contentRect.midY - scaled.height / 2,
                        width: scaled.width,
                        height: scaled.height
                    )
                    
                    // Calculate offsets
                    let imageAspect = srcSize.width / srcSize.height
                    let containerAspect = contentRect.width / contentRect.height
                    
                    let maxOffsetX: CGFloat
                    if imageAspect > containerAspect {
                        let imageWidth = contentRect.height * imageAspect
                        let overflow = imageWidth - contentRect.width
                        maxOffsetX = overflow / 2
                    } else {
                        maxOffsetX = 0
                    }
                    
                    let maxOffsetY: CGFloat
                    if imageAspect < containerAspect {
                        let imageHeight = contentRect.width / imageAspect
                        let overflow = imageHeight - contentRect.height
                        maxOffsetY = overflow / 2
                    } else {
                        maxOffsetY = 0
                    }
                    
                    // Apply the offsets
                    let offsetX = CGFloat(item.offsetX) * maxOffsetX
                    let offsetY = CGFloat(item.offsetY) * maxOffsetY
                    drawRect.origin.x += offsetX
                    drawRect.origin.y += offsetY
                    
                    // Draw the image with clipping to content rect
                    ctx.saveGState()
                    ctx.clip(to: contentRect)
                    ctx.draw(cg, in: drawRect)
                    ctx.restoreGState()
                } else {
                    // No border case - just draw the image fitted to the canvas
                    let srcSize = CGSize(width: cg.width, height: cg.height)
                    let scaled = zoomToFill
                        ? aspectFillSize(source: srcSize, into: canvasSize)
                        : aspectFitSize(source: srcSize, into: canvasSize)
                    
                    let drawRect = CGRect(
                        x: (canvasSize.width - scaled.width) / 2,
                        y: (canvasSize.height - scaled.height) / 2,
                        width: scaled.width,
                        height: scaled.height
                    )
                    
                    ctx.draw(cg, in: drawRect)
                }
                
                // Write out the image
                guard let outCG = ctx.makeImage() else { return }
                let outURL = outputDir.appendingPathComponent(String(format: "image_%03d.jpg", idx + 1))
                do {
                    try writeJPEG(outCG, to: outURL, quality: 0.95)
                    written.append(outURL)
                } catch {
                    // skip this image and continue
                }
            }
        }
        
        return written
    }

    // MARK: - Reel export (video) --------------------------------------------

    /// Builds a portrait reel (e.g. 1080×1920) MP4 at higher bitrate.
    /// `borderPx`/`background` behave like the carousel (in pixels of output size).
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
        // Using profile strings to avoid SDK-private constants
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
            throw NSError(domain: "ImageProcessor", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot add input to writer"])
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw NSError(domain: "ImageProcessor", code: -11, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"])
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let framesPerImage = max(1, Int(round(Double(fps) * secondsPerImage)))
        var currentTime = CMTime.zero

        writer.startSession(atSourceTime: .zero)

        // Use 3x border for reels as requested
        let reelBorderPx = Int(Double(borderPx) * 3.0)

        for item in images {
            autoreleasepool {
                guard let cg = loadCGImage(url: item.url) else { return }
                guard let pixelBuffer = makePixelBufferForReel(from: cg,
                                                              item: item,
                                                              size: targetSize,
                                                              borderPx: reelBorderPx,
                                                              zoomToFill: zoomToFill,
                                                              background: background)
                else { return }

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
            throw NSError(domain: "ImageProcessor", code: -12, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "Failed to finalize video"])
        }
    }

    // MARK: - Helpers ---------------------------------------------------------

    private static func loadCGImage(url: URL) -> CGImage? {
        // Prefer CGImageSource for consistent color management
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary) {
            return cg
        }
        // Fallback via NSImage if needed
        guard let nsimg = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: nsimg.size)
        return nsimg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

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

    private static func writeJPEG(_ cg: CGImage, to url: URL, quality: CGFloat) throws {
        let type = UTType.jpeg.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw NSError(domain: "ImageProcessor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }
        let props = [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        if !CGImageDestinationFinalize(dest) {
            throw NSError(domain: "ImageProcessor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to write JPEG"])
        }
    }

    /// Specialized pixel buffer creation for reel videos
    private static func makePixelBufferForReel(from cg: CGImage,
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

        // BGRA on Apple is little-endian; specify this so channels map correctly.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
                         CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(data: base,
                                  width: Int(size.width),
                                  height: Int(size.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: bitmapInfo)
        else { return nil }

        // Convert background to sRGB color space for consistency
        let bg = (background.usingColorSpace(.sRGB) ?? background)
        
        // Fill the entire canvas with the border color first
        ctx.setFillColor(bg.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        // Only process border if it's greater than zero
        if borderPx > 0 {
            let borderWidth = CGFloat(borderPx)
            
            // Create a content rectangle inset by the border width
            let contentRect = CGRect(
                x: borderWidth,
                y: borderWidth,
                width: size.width - borderWidth * 2,
                height: size.height - borderWidth * 2
            )
            
            // Calculate scaled image size
            let srcSize = CGSize(width: cg.width, height: cg.height)
            let scaled = zoomToFill
                ? aspectFillSize(source: srcSize, into: contentRect.size)
                : aspectFitSize(source: srcSize, into: contentRect.size)
            
            // Center the image in the content rect
            var drawRect = CGRect(
                x: contentRect.midX - scaled.width / 2,
                y: contentRect.midY - scaled.height / 2,
                width: scaled.width,
                height: scaled.height
            )
            
            // Calculate and apply position offsets
            let imageAspect = srcSize.width / srcSize.height
            let containerAspect = contentRect.width / contentRect.height
            
            let maxOffsetX: CGFloat
            if imageAspect > containerAspect {
                let imageWidth = contentRect.height * imageAspect
                let overflow = imageWidth - contentRect.width
                maxOffsetX = overflow / 2
            } else {
                maxOffsetX = 0
            }
            
            let maxOffsetY: CGFloat
            if imageAspect < containerAspect {
                let imageHeight = contentRect.width / imageAspect
                let overflow = imageHeight - contentRect.height
                maxOffsetY = overflow / 2
            } else {
                maxOffsetY = 0
            }
            
            // Apply offsets
            let offsetX = CGFloat(item.offsetX) * maxOffsetX
            let offsetY = CGFloat(item.offsetY) * maxOffsetY
            drawRect.origin.x += offsetX
            drawRect.origin.y += offsetY
            
            // Draw the image with clipping to content rect
            ctx.saveGState()
            ctx.clip(to: contentRect)
            ctx.draw(cg, in: drawRect)
            ctx.restoreGState()
        } else {
            // No border - draw the image to fit the entire canvas
            let srcSize = CGSize(width: cg.width, height: cg.height)
            let scaled = zoomToFill
                ? aspectFillSize(source: srcSize, into: size)
                : aspectFitSize(source: srcSize, into: size)
            
            let drawRect = CGRect(
                x: (size.width - scaled.width) / 2,
                y: (size.height - scaled.height) / 2,
                width: scaled.width,
                height: scaled.height
            )
            
            ctx.draw(cg, in: drawRect)
        }

        return pixelBuffer
    }
}
