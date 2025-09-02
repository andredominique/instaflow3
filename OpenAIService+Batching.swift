import Foundation

// MARK: - Batching Extensions for OpenAIService
private extension OpenAIService {
    // Configuration for batching
    struct BatchConfig {
        static let batchSize = 6 // Process 6 images at a time
        static let delayBetweenBatches: UInt64 = 500_000_000 // 0.5 second delay
        
        // Progress scaling helpers
        static func scaledProgress(forImage imageIndex: Int, totalImages: Int, batchProgress: Double) -> Double {
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
        print("[OpenAIService] Starting batched processing of \(urls.count) images")
        var imageParts: [MMPart] = []
        let totalImages = urls.count
        
        // Split into batches
        let batches = stride(from: 0, to: urls.count, by: BatchConfig.batchSize).map {
            Array(urls[$0..<min($0 + BatchConfig.batchSize, urls.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            print("[OpenAIService] Processing batch \(batchIndex + 1)/\(batches.count) with \(batch.count) images")
            
            // Process each image in the current batch
            for (imageIndexInBatch, url) in batch.enumerated() {
                let overallImageIndex = batchIndex * BatchConfig.batchSize + imageIndexInBatch
                
                do {
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
                        imageParts.append(.imageURL(.init(url: dataURL)))
                        uploadCompleteHandler(url)
                        
                        // Memory cleanup hint
                        autoreleasepool { }
                    } else {
                        let error = NSError(domain: "OpenAIService", code: 100,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
                        uploadErrorHandler(url, error)
                    }
                } catch {
                    print("[OpenAIService] Failed to process image: \(error.localizedDescription)")
                    uploadErrorHandler(url, error)
                }
            }
            
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