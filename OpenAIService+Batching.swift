import Foundation

// MARK: - Batching Extensions for OpenAIService
extension OpenAIService {
    // Configuration for batching
    struct BatchConfig {
        static let batchSize = 6 // Process 6 images at a time
        static let delayBetweenBatches: UInt64 = 500_000_000 // 0.5 second delay
        static let networkTimeout: TimeInterval = 120.0 // 120 seconds timeout
        
        // Progress scaling helpers
        static func scaledProgress(forImage imageIndex: Int, totalImages: Int, batchProgress: Double) -> Double {
            let imageProgress = (Double(imageIndex) + batchProgress) / Double(totalImages)
            return min(max(imageProgress, 0.0), 1.0)
        }
    }
    
    // Helper to split URLs into batches with improved memory management
    func processBatchedImages(
        urls: [URL],
        maxSize: CGFloat,
        quality: CGFloat,
        uploadProgressHandler: @escaping (URL, Double) -> Void,
        uploadCompleteHandler: @escaping (URL) -> Void,
        uploadErrorHandler: @escaping (URL, Error) -> Void
    ) async throws -> [MMPart] {
        print("[OpenAIService] Starting batched processing of \(urls.count) images")
        var imageParts: [MMPart] = []
        let totalImages = urls.count
        
        // Split into batches
        let batches = stride(from: 0, to: urls.count, by: BatchConfig.batchSize).map {
            Array(urls[$0..<min($0 + BatchConfig.batchSize, urls.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            print("[OpenAIService] Processing batch \(batchIndex + 1)/\(batches.count) with \(batch.count) images")
            
            // Use autoreleasepool for each batch to manage memory better
            let batchResults = try await autoreleasepool {
                var batchParts: [MMPart] = []
                
                // Process each image in the current batch
                for (imageIndexInBatch, url) in batch.enumerated() {
                    let overallImageIndex = batchIndex * BatchConfig.batchSize + imageIndexInBatch
                    print("[OpenAIService] Processing image \(overallImageIndex + 1)/\(totalImages): \(url.lastPathComponent)")
                    
                    do {
                        // Report initial progress for this image
                        let initialProgress = BatchConfig.scaledProgress(
                            forImage: overallImageIndex, 
                            totalImages: totalImages, 
                            batchProgress: 0.1
                        )
                        uploadProgressHandler(url, initialProgress)
                        
                        if let dataURL = try Self.encodeImageDataURLWithThrows(
                            at: url,
                            maxSize: maxSize,
                            quality: quality,
                            progressHandler: { batchProgress in
                                // Scale the progress relative to overall process
                                let scaledProgress = BatchConfig.scaledProgress(
                                    forImage: overallImageIndex,
                                    totalImages: totalImages,
                                    batchProgress: batchProgress
                                )
                                uploadProgressHandler(url, scaledProgress)
                            }
                        ) {
                            batchParts.append(.imageURL(.init(url: dataURL)))
                            uploadCompleteHandler(url)
                            print("[OpenAIService] ✅ Successfully processed image \(overallImageIndex + 1)")
                        } else {
                            let error = NSError(domain: "OpenAIService", code: 100,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
                            print("[OpenAIService] ❌ Failed to encode image \(overallImageIndex + 1): returned nil")
                            uploadErrorHandler(url, error)
                        }
                    } catch {
                        print("[OpenAIService] ❌ Failed to process image \(overallImageIndex + 1): \(error.localizedDescription)")
                        uploadErrorHandler(url, error)
                    }
                }
                
                return batchParts
            }
            
            imageParts.append(contentsOf: batchResults)
            
            // Add delay between batches (except for the last batch)
            if batchIndex < batches.count - 1 {
                print("[OpenAIService] Batch \(batchIndex + 1) complete - waiting before next batch")
                try await Task.sleep(nanoseconds: BatchConfig.delayBetweenBatches)
            }
        }
        
        print("[OpenAIService] Batch processing complete - processed \(imageParts.count) images")
        return imageParts
    }
}