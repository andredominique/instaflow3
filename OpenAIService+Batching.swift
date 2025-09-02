import Foundation

// MARK: - Batching Extensions for OpenAIService
extension OpenAIService {
    // Configuration for batching
    struct BatchConfig {
        let batchSize: Int = 6
        let delayBetweenBatches: TimeInterval = 0.5
        let networkTimeout: TimeInterval = 120
        
        // Progress scaling helpers
        func scaledProgress(forImage imageIndex: Int, totalImages: Int, batchProgress: Double) -> Double {
            let imageProgress = (Double(imageIndex) + batchProgress) / Double(totalImages)
            return min(max(imageProgress, 0.0), 1.0)
        }
    }
    
    // Helper to split URLs into batches
    func processBatchedImages(
        urls: [URL],
        maxSize: CGFloat,
        quality: CGFloat,
        uploadProgressHandler: @escaping (URL, Double) -> Void,
        uploadCompleteHandler: @escaping (URL) -> Void,
        uploadErrorHandler: @escaping (URL, Error) -> Void
    ) async throws -> [MMPart] {
        let config = BatchConfig()
        print("[OpenAIService] Starting batched processing of \(urls.count) images (batch size: \(config.batchSize))")
        var imageParts: [MMPart] = []
        let totalImages = urls.count
        
        // Split into batches
        let batches = stride(from: 0, to: urls.count, by: config.batchSize).map {
            Array(urls[$0..<min($0 + config.batchSize, urls.count)])
        }
        
        print("[OpenAIService] Split into \(batches.count) batches")
        
        for (batchIndex, batch) in batches.enumerated() {
            print("[OpenAIService] ========== PROCESSING BATCH \(batchIndex + 1)/\(batches.count) ==========")
            print("[OpenAIService] Batch contains \(batch.count) images")
            
            // Use autoreleasepool for each batch to manage memory
            let batchResults = try await withUnsafeThrowingContinuation { continuation in
                Task {
                    autoreleasepool {
                        var batchParts: [MMPart] = []
                        var batchError: Error?
                        
                        // Process each image in the current batch
                        for (imageIndexInBatch, url) in batch.enumerated() {
                            let overallImageIndex = batchIndex * config.batchSize + imageIndexInBatch
                            
                            print("[OpenAIService] Processing image \(overallImageIndex + 1)/\(totalImages): \(url.lastPathComponent)")
                            
                            do {
                                if let dataURL = try Self.encodeImageDataURLWithThrows(
                                    at: url,
                                    maxSize: maxSize,
                                    quality: quality,
                                    progressHandler: { batchProgress in
                                        // Scale the progress relative to overall process
                                        let scaledProgress = config.scaledProgress(
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
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to encode image \(url.lastPathComponent)"])
                                    uploadErrorHandler(url, error)
                                    print("[OpenAIService] ❌ Failed to encode image \(overallImageIndex + 1)")
                                }
                            } catch {
                                print("[OpenAIService] ❌ Failed to process image \(overallImageIndex + 1): \(error.localizedDescription)")
                                uploadErrorHandler(url, error)
                                if batchError == nil {
                                    batchError = error
                                }
                            }
                        }
                        
                        print("[OpenAIService] Batch \(batchIndex + 1) processed - \(batchParts.count) successful images")
                        
                        if let error = batchError {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: batchParts)
                        }
                    }
                }
            }
            
            imageParts.append(contentsOf: batchResults)
            
            // Add delay between batches (except for the last batch)
            if batchIndex < batches.count - 1 {
                let delayNanoseconds = UInt64(config.delayBetweenBatches * 1_000_000_000)
                print("[OpenAIService] Batch \(batchIndex + 1) complete - waiting \(config.delayBetweenBatches)s before next batch")
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        
        print("[OpenAIService] ========== BATCH PROCESSING COMPLETE ==========")
        print("[OpenAIService] Successfully processed \(imageParts.count)/\(totalImages) images")
        return imageParts
    }
}