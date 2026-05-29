import Foundation
import CoreGraphics
import NetworkImage
import MemosKit
import ImageIO

public final class MemosImageLoader: NetworkImageLoader, @unchecked Sendable {
    public static let shared = MemosImageLoader()
    
    private let cache: NetworkImageCache
    private let session: URLSession
    private let auth: MemosAuth
    
    private actor TaskManager {
        private var ongoingTasks: [URL: Task<CGImage, Error>] = [:]
        
        func getOrCreateTask(url: URL, operation: @escaping @Sendable () async throws -> CGImage) async throws -> CGImage {
            if let task = ongoingTasks[url] {
                return try await task.value
            }
            
            let task = Task<CGImage, Error> {
                try await operation()
            }
            ongoingTasks[url] = task
            
            do {
                let image = try await task.value
                ongoingTasks.removeValue(forKey: url)
                return image
            } catch {
                ongoingTasks.removeValue(forKey: url)
                throw error
            }
        }
    }
    
    private let taskManager = TaskManager()
    
    public init(
        cache: NetworkImageCache = DefaultNetworkImageCache.shared,
        session: URLSession? = nil,
        auth: MemosAuth = .shared
    ) {
        self.cache = cache
        self.auth = auth
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.timeoutIntervalForRequest = 15
            configuration.httpAdditionalHeaders = ["Accept": "image/*"]
            self.session = URLSession(configuration: configuration)
        }
    }
    
    public func image(from url: URL) async throws -> CGImage {
        // 1. Check in-memory cache first
        if let cachedImage = cache.image(for: url) {
            return cachedImage
        }
        
        // 2. Load image (with task serialization to avoid duplicate parallel requests)
        return try await taskManager.getOrCreateTask(url: url) { [weak self] in
            guard let self = self else { throw URLError(.cancelled) }
            
            var request = URLRequest(url: url)
            
            // Check if request is pointing to Memos server
            let isMemosURL: Bool
            if let baseURL = self.auth.baseURL,
               let host = url.host,
               let baseHost = baseURL.host,
               host.lowercased() == baseHost.lowercased() {
                let port = url.port ?? (url.scheme == "https" ? 443 : 80)
                let basePort = baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80)
                isMemosURL = (port == basePort) && url.path.contains("/file/")
            } else {
                isMemosURL = false
            }
            
            if isMemosURL {
                if let pat = self.auth.pat {
                    request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
                }
            }
            
            let (data, response) = try await self.session.data(for: request)
            
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                  200..<300 ~= statusCode
            else {
                throw URLError(.badServerResponse)
            }
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
            else {
                throw URLError(.cannotDecodeContentData)
            }
            
            // 3. Store in cache
            self.cache.setImage(image, for: url)
            return image
        }
    }
}
