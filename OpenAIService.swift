import Foundation
import AppKit

/// OpenAI client with text + image (vision) streaming support.
/// API key is stored in UserDefaults under "openai_api_key".
@MainActor
final class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    private init() {}

    // MARK: - API Key

    func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openai_api_key")
    }

    func currentAPIKey() -> String? {
        UserDefaults.standard.string(forKey: "openai_api_key")
    }

    func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "openai_api_key")
    }

    var apiKeyAvailable: Bool {
        let k = currentAPIKey() ?? ""
        return !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Config

    private var apiKey: String? { currentAPIKey() }

    /// Text-only default. For images we still use this model; it accepts image inputs too.
    private let defaultModel = "gpt-4o-mini"

    // MARK: - Public (simple captions, no images)

    func generateCaption(prompt: String, context: [String] = []) async throws -> String {
        var history: [(role: String, content: String)] = []
        for c in context { history.append(("user", c)) }
        history.append(("user", prompt))
        return try await chatOnce(history: history)
    }

    // Fixed version - explicitly call the basic version without progress tracking
    func generateCaption(prompt: String, imageURLs: [URL]) async throws -> String {
        // Convenience non-streaming path when caller wants a one-shot caption with images.
        return try await chatOnceWithImagesBasic(
            preHistory: [],
            userPrompt: prompt,
            imageURLs: imageURLs
        )
    }

    // MARK: - Chat (text-only)

    func chatOnce(history: [(role: String, content: String)], model: String? = nil) async throws -> String {
        let req = ChatRequestText(
            model: model ?? defaultModel,
            messages: history.map { .init(role: $0.role, content: $0.content) },
            stream: false
        )
        let data = try await postJSON(to: "https://api.openai.com/v1/chat/completions", body: req)
        let decoded = try JSONDecoder().decode(ChatResponseText.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    func chatStream(
        history: [(role: String, content: String)],
        model: String? = nil,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let req = ChatRequestText(
            model: model ?? defaultModel,
            messages: history.map { .init(role: $0.role, content: $0.content) },
            stream: true
        )
        return try await streamRequest(req, onDelta: onDelta)
    }

    // MARK: - Chat (text + images, streaming) with Upload Progress

    /// Streams a reply where the final user message contains the prompt + attached images.
    /// This version adds upload progress tracking.
    func chatStreamWithImagesProgress(
        preHistory: [(role: String, content: String)],
        userPrompt: String,
        imageURLs: [URL],
        uploadProgressHandler: @escaping (URL, Double) -> Void,
        uploadCompleteHandler: @escaping (URL) -> Void,
        uploadErrorHandler: @escaping (URL, Error) -> Void,
        model: String? = nil,
        downscaleMax: CGFloat = 1024, // pixels longest edge
        jpegQuality: CGFloat = 0.7,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        print("[OpenAIService] ========== STARTING IMAGE STREAM WITH PROGRESS TRACKING ==========")
        print("[OpenAIService] Processing \(imageURLs.count) images for streaming")
        print("[OpenAIService] Model: \(model ?? defaultModel)")
        print("[OpenAIService] Downscale max: \(downscaleMax)")
        print("[OpenAIService] JPEG quality: \(jpegQuality)")
        
        // Pre-validate all images before processing
        for (index, url) in imageURLs.enumerated() {
            print("[OpenAIService] Pre-validating image \(index): \(url.lastPathComponent)")
            
            // Check file existence
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            print("[OpenAIService] File exists: \(fileExists)")
            
            if fileExists {
                // Check file size
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        print("[OpenAIService] File size: \(fileSize) bytes")
                    }
                } catch {
                    print("[OpenAIService] ERROR getting file attributes: \(error.localizedDescription)")
                }
                
                // Test NSImage loading
                if let nsImage = NSImage(contentsOf: url) {
                    print("[OpenAIService] NSImage loaded successfully: \(nsImage.size)")
                    
                    // Test TIFF representation
                    if let tiff = nsImage.tiffRepresentation {
                        print("[OpenAIService] TIFF representation: \(tiff.count) bytes")
                        
                        // Test bitmap creation
                        if let bitmap = NSBitmapImageRep(data: tiff) {
                            print("[OpenAIService] Bitmap representation created successfully")
                        } else {
                            print("[OpenAIService] ERROR: Cannot create bitmap representation")
                        }
                    } else {
                        print("[OpenAIService] ERROR: Cannot get TIFF representation")
                    }
                } else {
                    print("[OpenAIService] ERROR: Cannot load NSImage")
                }
            }
        }
        
        // 1) Convert images to data-URLs (base64 JPEG) and build content parts.
        var imageParts: [MMPart] = []
        var successCount = 0
        
        for (index, url) in imageURLs.enumerated() {
            print("[OpenAIService] ========== PROCESSING IMAGE \(index) ==========")
            
            // Report initial progress
            uploadProgressHandler(url, 0.1)
            
            do {
                // Simulate progress steps for image loading
                uploadProgressHandler(url, 0.2)
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
                
                if let dataURL = try Self.encodeImageDataURLWithThrows(
                    at: url,
            let batchSize = 5
            var index = 0
            while index < imageURLs.count {
                let batch = Array(imageURLs[index..<min(index+batchSize, imageURLs.count)])
                await withTaskGroup(of: Void.self) { group in
                    for url in batch {
                        group.addTask {
                            let batchIndex = imageURLs.firstIndex(of: url) ?? 0
                            print("[OpenAIService] ========== PROCESSING IMAGE \(batchIndex) ==========")
                            uploadProgressHandler(url, 0.1)
                            do {
                                uploadProgressHandler(url, 0.2)
                                try await Task.sleep(nanoseconds: 100_000_000)
                                if let dataURL = try Self.encodeImageDataURLWithThrows(
                                    at: url,
                                    maxSize: downscaleMax,
                                    quality: jpegQuality,
                                    progressHandler: { progress in
                                        let scaledProgress = 0.3 + (progress * 0.6)
                                        uploadProgressHandler(url, scaledProgress)
                                    }
                                ) {
                                    await MainActor.run {
                                        imageParts.append(.imageURL(.init(url: dataURL)))
                                        successCount += 1
                                    }
                                    print("[OpenAIService] ✅ Successfully encoded image \(batchIndex)")
                                    uploadProgressHandler(url, 1.0)
                                    uploadCompleteHandler(url)
                                } else {
                                    print("[OpenAIService] ❌ Failed to encode image \(batchIndex) - returned nil")
                                    let error = NSError(domain: "OpenAIService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
                                    uploadErrorHandler(url, error)
                                }
                            } catch {
                                print("[OpenAIService] ❌ Failed to encode image \(batchIndex) with error: \(error.localizedDescription)")
                                uploadErrorHandler(url, error)
                            }
                        }
                    }
                    await group.waitForAll()
                }
                index += batchSize
            }
            }
            throw error
        }
        
        print("[OpenAIService] Successfully processed \(successCount) out of \(imageURLs.count) images")

        // 2) Build message list: previous text-only turns + final multimodal user turn.
        var messages: [MMMessage] = preHistory.map { .init(role: $0.role, content: .string($0.content)) }
        var finalParts: [MMPart] = [.text(.init(text: userPrompt))]
        finalParts.append(contentsOf: imageParts)
        messages.append(.init(role: "user", content: .parts(finalParts)))

        print("[OpenAIService] Built \(messages.count) messages with \(finalParts.count) parts in final message")
        
        let req = ChatRequestMM(model: model ?? defaultModel, messages: messages, stream: true)
        
        // Log request structure (without the actual base64 data)
        print("[OpenAIService] Request model: \(req.model)")
        print("[OpenAIService] Request stream: \(req.stream)")
        print("[OpenAIService] Messages count: \(req.messages.count)")
        
        do {
            let result = try await streamRequest(req, onDelta: onDelta)
            print("[OpenAIService] ✅ Stream completed successfully")
            return result
        } catch {
            print("[OpenAIService] ❌ Stream failed with error: \(error)")
            throw error
        }
    }
    
    /// Original streaming method (without progress tracking)
    func chatStreamWithImages(
        preHistory: [(role: String, content: String)],
        userPrompt: String,
        imageURLs: [URL],
        model: String? = nil,
        downscaleMax: CGFloat = 1024, // pixels longest edge
        jpegQuality: CGFloat = 0.7,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        // Call the version with progress tracking but with empty handlers
        return try await chatStreamWithImagesProgress(
            preHistory: preHistory,
            userPrompt: userPrompt,
            imageURLs: imageURLs,
            uploadProgressHandler: { _, _ in },
            uploadCompleteHandler: { _ in },
            uploadErrorHandler: { _, _ in },
            model: model,
            downscaleMax: downscaleMax,
            jpegQuality: jpegQuality,
            onDelta: onDelta
        )
    }

    /// Non-streaming version with progress tracking
    func chatOnceWithImagesProgress(
        preHistory: [(role: String, content: String)],
        userPrompt: String,
        imageURLs: [URL],
        uploadProgressHandler: @escaping (URL, Double) -> Void,
        uploadCompleteHandler: @escaping (URL) -> Void,
        uploadErrorHandler: @escaping (URL, Error) -> Void,
        model: String? = nil,
        downscaleMax: CGFloat = 1024,
        jpegQuality: CGFloat = 0.7
    ) async throws -> String {
        print("[OpenAIService] ========== STARTING IMAGE ONE-SHOT WITH PROGRESS TRACKING ==========")
        print("[OpenAIService] Processing \(imageURLs.count) images for one-shot")
        
        var imageParts: [MMPart] = []
        var successCount = 0
        
        for (index, url) in imageURLs.enumerated() {
            print("[OpenAIService] Processing image \(index): \(url.lastPathComponent)")
            
            // Report initial progress
            uploadProgressHandler(url, 0.1)
            
            do {
                // Simulate progress steps for image loading
                uploadProgressHandler(url, 0.2)
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
                
                if let dataURL = try Self.encodeImageDataURLWithThrows(
                    at: url,
                    maxSize: downscaleMax,
                    quality: jpegQuality,
                    progressHandler: { progress in
                        // Scale progress from 0.3 to 0.9 (reserving 0.1-0.3 for loading and 0.9-1.0 for finalizing)
                        let scaledProgress = 0.3 + (progress * 0.6)
                        uploadProgressHandler(url, scaledProgress)
                    }
                ) {
                    imageParts.append(.imageURL(.init(url: dataURL)))
                    successCount += 1
                    print("[OpenAIService] ✅ Successfully encoded image \(index)")
                    
                    // Final progress and completion
                    uploadProgressHandler(url, 1.0)
                    uploadCompleteHandler(url)
                } else {
                    print("[OpenAIService] ❌ Failed to encode image \(index) - returned nil")
                    let error = NSError(domain: "OpenAIService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
                    uploadErrorHandler(url, error)
                }
            } catch {
                print("[OpenAIService] ❌ Failed to encode image \(index) with error: \(error.localizedDescription)")
                uploadErrorHandler(url, error)
                // Continue with other images instead of failing completely
            }
        }
        
        guard !imageParts.isEmpty else {
            let errorMsg = "No images could be processed successfully out of \(imageURLs.count) images"
            print("[OpenAIService] FATAL: \(errorMsg)")
            let error = OpenAIError.custom(errorMsg)
            // Mark all images as failed if not already marked
            for url in imageURLs {
                uploadErrorHandler(url, error)
            }
            throw error
        }
        
        print("[OpenAIService] Successfully processed \(successCount) out of \(imageURLs.count) images")

        var messages: [MMMessage] = preHistory.map { .init(role: $0.role, content: .string($0.content)) }
        var finalParts: [MMPart] = [.text(.init(text: userPrompt))]
        finalParts.append(contentsOf: imageParts)
        messages.append(.init(role: "user", content: .parts(finalParts)))

        let req = ChatRequestMM(model: model ?? defaultModel, messages: messages, stream: false)
        
        do {
            let data = try await postJSON(to: "https://api.openai.com/v1/chat/completions", body: req)
            let decoded = try JSONDecoder().decode(ChatResponseMM.self, from: data)
            let result = decoded.choices.first?.message.contentString ?? ""
            print("[OpenAIService] ✅ One-shot completed successfully")
            return result
        } catch {
            print("[OpenAIService] ❌ One-shot failed with error: \(error)")
            throw error
        }
    }
    
    /// Original non-streaming method (without progress tracking)
    func chatOnceWithImagesBasic(
        preHistory: [(role: String, content: String)],
        userPrompt: String,
        imageURLs: [URL],
        model: String? = nil,
        downscaleMax: CGFloat = 1024,
        jpegQuality: CGFloat = 0.7
    ) async throws -> String {
        // Call the version with progress tracking but with empty handlers
        return try await chatOnceWithImagesProgress(
            preHistory: preHistory,
            userPrompt: userPrompt,
            imageURLs: imageURLs,
            uploadProgressHandler: { _, _ in },
            uploadCompleteHandler: { _ in },
            uploadErrorHandler: { _, _ in },
            model: model,
            downscaleMax: downscaleMax,
            jpegQuality: jpegQuality
        )
    }

    // MARK: - Streaming core

    private func streamRequest<T: Encodable>(
        _ body: T,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        print("[OpenAIService] Starting stream request...")
        
        guard let key = apiKey, !key.isEmpty else {
            print("[OpenAIService] ERROR: Missing API key")
            throw OpenAIError.missingKey
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            print("[OpenAIService] Request body encoded successfully, size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            print("[OpenAIService] ERROR: Failed to encode request body: \(error)")
            throw error
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        print("[OpenAIService] Got response from server")

        if let http = response as? HTTPURLResponse {
            print("[OpenAIService] HTTP Status: \(http.statusCode)")
            if !(200..<300).contains(http.statusCode) {
                var data = Data()
                for try await b in bytes { data.append(b) } // append single bytes
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[OpenAIService] ERROR Response Body: \(body)")
                throw OpenAIError.http(status: http.statusCode, body: body)
            }
        }

        var final = ""
        var chunkCount = 0
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                print("[OpenAIService] Stream completed with [DONE]")
                break
            }
            guard let data = payload.data(using: .utf8) else { continue }

            if let delta = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) {
                if let piece = delta.choices.first?.delta.content, !piece.isEmpty {
                    final += piece
                    chunkCount += 1
                    onDelta(piece)
                }
            } else {
                print("[OpenAIService] Failed to decode chunk: \(payload)")
            }
        }
        
        print("[OpenAIService] Stream finished. Received \(chunkCount) chunks, total length: \(final.count)")
        return final
    }

    // MARK: - Networking helper

    private func postJSON<T: Encodable>(to urlString: String, body: T) async throws -> Data {
        print("[OpenAIService] Making POST request to: \(urlString)")
        
        guard let key = apiKey, !key.isEmpty else {
            print("[OpenAIService] ERROR: Missing API key")
            throw OpenAIError.missingKey
        }
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            print("[OpenAIService] Request body size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            print("[OpenAIService] ERROR: Failed to encode request: \(error)")
            throw error
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            print("[OpenAIService] HTTP Status: \(http.statusCode)")
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[OpenAIService] ERROR Response: \(body)")
                throw OpenAIError.http(status: http.statusCode, body: body)
            }
        }
        
        print("[OpenAIService] POST successful, response size: \(data.count) bytes")
        return data
    }

    // MARK: - Image encoding with detailed error handling and progress tracking

    /// Enhanced version with progress tracking
    private static func encodeImageDataURLWithThrows(
        at url: URL,
        maxSize: CGFloat,
        quality: CGFloat,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) throws -> String? {
        print("[OpenAIService] ========== ENCODING IMAGE ==========")
        print("[OpenAIService] Path: \(url.path)")
        print("[OpenAIService] Max size: \(maxSize)")
        print("[OpenAIService] Quality: \(quality)")
        
        // Step 1: Check file existence (10% progress)
        progressHandler(0.1)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = NSError(domain: "ImageError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "File does not exist at path: \(url.path)"
            ])
            print("[OpenAIService] ❌ Step 1 failed: \(error.localizedDescription)")
            throw error
        }
        print("[OpenAIService] ✅ Step 1: File exists")
        
        // Step 2: Load NSImage (20% progress)
        progressHandler(0.2)
        guard let nsImage = NSImage(contentsOf: url) else {
            let error = NSError(domain: "ImageError", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot load NSImage from: \(url.path)"
            ])
            print("[OpenAIService] ❌ Step 2 failed: \(error.localizedDescription)")
            throw error
        }
        print("[OpenAIService] ✅ Step 2: NSImage loaded, size: \(nsImage.size)")
        
        // Step 3: Validate image size (30% progress)
        progressHandler(0.3)
        let originalSize = nsImage.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            let error = NSError(domain: "ImageError", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid image dimensions: \(originalSize)"
            ])
            print("[OpenAIService] ❌ Step 3 failed: \(error.localizedDescription)")
            throw error
        }
        print("[OpenAIService] ✅ Step 3: Valid dimensions")
        
        // Step 4: Resize image (50% progress)
        progressHandler(0.5)
        let scaled = try nsImage.resizedWithThrows(longEdge: maxSize)
        print("[OpenAIService] ✅ Step 4: Image resized to: \(scaled.size)")
        
        // Step 5: Convert to JPEG (70% progress)
        progressHandler(0.7)
        guard let jpeg = try scaled.jpegDataWithThrows(quality: quality) else {
            let error = NSError(domain: "ImageError", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Failed to convert image to JPEG"
            ])
            print("[OpenAIService] ❌ Step 5 failed: \(error.localizedDescription)")
            throw error
        }
        print("[OpenAIService] ✅ Step 5: JPEG created, size: \(jpeg.count) bytes")
        
        // Step 6: Base64 encode (90% progress)
        progressHandler(0.9)
        let b64 = jpeg.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(b64)"
        print("[OpenAIService] ✅ Step 6: Base64 encoded, data URL length: \(dataURL.count)")
        
        // Final progress (100%)
        progressHandler(1.0)
        print("[OpenAIService] ========== ENCODING COMPLETE ==========")
        return dataURL
    }

    /// Original version without progress tracking
    private static func encodeImageDataURL(at url: URL, maxSize: CGFloat, quality: CGFloat) -> String? {
        do {
            return try encodeImageDataURLWithThrows(at: url, maxSize: maxSize, quality: quality)
        } catch {
            print("[OpenAIService] encodeImageDataURL failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Original version for backward compatibility
    private static func encodeImageDataURLWithThrows(at url: URL, maxSize: CGFloat, quality: CGFloat) throws -> String? {
        // Call the enhanced version with empty progress handler
        return try encodeImageDataURLWithThrows(at: url, maxSize: maxSize, quality: quality, progressHandler: { _ in })
    }
}

// MARK: - Wire types (text-only)

struct ChatRequestText: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct ChatResponseText: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Wire types (multimodal)
            let batchSize = 5
            var index = 0
            while index < imageURLs.count {
                let batch = Array(imageURLs[index..<min(index+batchSize, imageURLs.count)])
                await withTaskGroup(of: Void.self) { group in
                    for url in batch {
                        group.addTask {
                            let batchIndex = imageURLs.firstIndex(of: url) ?? 0
                            print("[OpenAIService] Processing image \(batchIndex): \(url.lastPathComponent)")
                            uploadProgressHandler(url, 0.1)
                            do {
                                uploadProgressHandler(url, 0.2)
                                try await Task.sleep(nanoseconds: 100_000_000)
                                if let dataURL = try Self.encodeImageDataURLWithThrows(
                                    at: url,
                                    maxSize: downscaleMax,
                                    quality: jpegQuality,
                                    progressHandler: { progress in
                                        let scaledProgress = 0.3 + (progress * 0.6)
                                        uploadProgressHandler(url, scaledProgress)
                                    }
                                ) {
                                    await MainActor.run {
                                        imageParts.append(.imageURL(.init(url: dataURL)))
                                        successCount += 1
                                    }
                                    print("[OpenAIService] ✅ Successfully encoded image \(batchIndex)")
                                    uploadProgressHandler(url, 1.0)
                                    uploadCompleteHandler(url)
                                } else {
                                    print("[OpenAIService] ❌ Failed to encode image \(batchIndex) - returned nil")
                                    let error = NSError(domain: "OpenAIService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
                                    uploadErrorHandler(url, error)
                                }
                            } catch {
                                print("[OpenAIService] ❌ Failed to encode image \(batchIndex) with error: \(error.localizedDescription)")
                                uploadErrorHandler(url, error)
                            }
                        }
                    }
                    await group.waitForAll()
                }
                index += batchSize
            }
        case .text(let t):
            try t.encode(to: encoder)
        case .imageURL(let i):
            try i.encode(to: encoder)
        }
    }

    struct TextPart: Encodable {
        let type = "text"
        let text: String
    }

    struct ImageURLPart: Encodable {
        let type = "image_url"
        let image_url: URLPayload

        init(url: String) {
            self.image_url = URLPayload(url: url)
        }

        struct URLPayload: Encodable { let url: String }
    }
}

// MARK: - FIXED: Updated ChatResponseMM to handle both string and array responses

struct ChatResponseMM: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: ContentType?
            
            // Handle both string and array responses from OpenAI
            enum ContentType: Decodable {
                case string(String)
                case parts([MMReturnPart])
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    
                    // Try to decode as string first (which is what we're getting)
                    if let stringValue = try? container.decode(String.self) {
                        self = .string(stringValue)
                        return
                    }
                    
                    // Try to decode as array (for future compatibility)
                    if let arrayValue = try? container.decode([MMReturnPart].self) {
                        self = .parts(arrayValue)
                        return
                    }
                    
                    throw DecodingError.typeMismatch(ContentType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string or array for content"))
                }
            }
            
            var contentString: String {
                switch content {
                case .string(let str):
                    return str
                case .parts(let parts):
                    return parts.compactMap { $0.text }.joined()
                case .none:
                    return ""
                }
            }
        }
        let message: Message
    }
    struct MMReturnPart: Decodable {
        let type: String
        let text: String?
    }
    let choices: [Choice]
}

struct ChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let role: String?
            let content: String? // streamed as plain text deltas
        }
        let delta: Delta
    }
    let choices: [Choice]
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case missingKey
    case http(status: Int, body: String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "OpenAI API key is missing. Add it in Settings."
        case .http(let status, let body):
            return "HTTP \(status): \(body)"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - NSImage helpers with error handling

private extension NSImage {
    func resizedWithThrows(longEdge: CGFloat) throws -> NSImage {
        print("[NSImage] Resizing with longEdge: \(longEdge)")
        
        guard longEdge > 0 else {
            print("[NSImage] longEdge <= 0, returning original")
            return self
        }
        
        let originalSize = self.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            print("[NSImage] Invalid original size, returning self")
            let error = NSError(domain: "NSImageError", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Invalid image dimensions for resize: \(originalSize)"
            ])
            throw error
        }
        
        // If image is already smaller than target, return as-is
        let maxDimension = max(originalSize.width, originalSize.height)
        if maxDimension <= longEdge {
            print("[NSImage] Image already smaller (\(maxDimension) <= \(longEdge)), no resize needed")
            return self
        }
        
        let aspect = originalSize.width / originalSize.height
        let targetSize: NSSize = (aspect >= 1)
            ? NSSize(width: longEdge, height: longEdge / aspect)
            : NSSize(width: longEdge * aspect, height: longEdge)
        
        print("[NSImage] Resizing from \(originalSize) to \(targetSize), aspect: \(aspect)")
        
        // Use a more robust resizing method
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        // Draw with high quality
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: originalSize),
                  operation: .copy,
                  fraction: 1.0)
        
        print("[NSImage] Resize complete")
        return newImage
    }

    func jpegDataWithThrows(quality: CGFloat) throws -> Data? {
        print("[NSImage] Converting to JPEG with quality: \(quality)")
        
        guard let tiff = tiffRepresentation else {
            let error = NSError(domain: "NSImageError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot get TIFF representation"
            ])
            print("[NSImage] ❌ TIFF representation failed")
            throw error
        }
        print("[NSImage] ✅ TIFF representation: \(tiff.count) bytes")
        
        guard let rep = NSBitmapImageRep(data: tiff) else {
            let error = NSError(domain: "NSImageError", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create bitmap representation"
            ])
            print("[NSImage] ❌ Bitmap representation failed")
            throw error
        }
        print("[NSImage] ✅ Bitmap representation created")
        
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            let error = NSError(domain: "NSImageError", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create JPEG representation"
            ])
            print("[NSImage] ❌ JPEG representation failed")
            throw error
        }
        
        print("[NSImage] ✅ JPEG created: \(jpegData.count) bytes")
        return jpegData
    }

    // Original methods for backward compatibility
    func resized(longEdge: CGFloat) -> NSImage {
        do {
            return try resizedWithThrows(longEdge: longEdge)
        } catch {
            print("[NSImage] resized failed: \(error.localizedDescription)")
            return self
        }
    }

    func jpegData(quality: CGFloat) -> Data? {
        do {
            return try jpegDataWithThrows(quality: quality)
        } catch {
            print("[NSImage] jpegData failed: \(error.localizedDescription)")
            return nil
        }
    }
}
