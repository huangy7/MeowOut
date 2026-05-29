// Tests/MeowOutTests/MemosImageLoaderTests.swift
import XCTest
@testable import MeowOut
import MemosKit
import NetworkImage
import CoreGraphics

final class MemosImageLoaderTests: XCTestCase {
    
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                return
            }
            
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        
        override func stopLoading() {}
    }
    
    // 1x1 transparent PNG data
    private let mockImageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!
    
    private var session: URLSession!
    
    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }
    
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }
    
    private func makeMockAuth(baseURL: URL, pat: String) throws -> MemosAuth {
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(baseURL: baseURL, pat: pat)
        return auth
    }
    
    func testMemosURLInterceptionAndAuthHeader() async throws {
        let mockBaseURL = URL(string: "https://memos-test.top:8080")!
        let mockToken = "mock_pat_token_abc"
        let mockAuth = try makeMockAuth(baseURL: mockBaseURL, pat: mockToken)
        
        let imageURL = URL(string: "https://memos-test.top:8080/file/attachments/123/img.png")!
        
        var headerValue: String?
        MockURLProtocol.requestHandler = { request in
            headerValue = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.mockImageData)
        }
        
        let loader = MemosImageLoader(
            cache: DefaultNetworkImageCache(countLimit: 1),
            session: session,
            auth: mockAuth
        )
        let _ = try await loader.image(from: imageURL)
        
        XCTAssertEqual(headerValue, "Bearer \(mockToken)")
    }
    
    func testMemosResourcesURLInterceptionAndAuthHeader() async throws {
        let mockBaseURL = URL(string: "https://memos-test.top:8080")!
        let mockToken = "mock_pat_token_abc"
        let mockAuth = try makeMockAuth(baseURL: mockBaseURL, pat: mockToken)
        
        let imageURL = URL(string: "https://memos-test.top:8080/file/resources/123/img.png")!
        
        var headerValue: String?
        MockURLProtocol.requestHandler = { request in
            headerValue = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.mockImageData)
        }
        
        let loader = MemosImageLoader(
            cache: DefaultNetworkImageCache(countLimit: 1),
            session: session,
            auth: mockAuth
        )
        let _ = try await loader.image(from: imageURL)
        
        XCTAssertEqual(headerValue, "Bearer \(mockToken)")
    }
    
    func testNonMemosURLDoesNotHaveAuthHeader() async throws {
        let mockBaseURL = URL(string: "https://memos-test.top:8080")!
        let mockToken = "mock_pat_token_abc"
        let mockAuth = try makeMockAuth(baseURL: mockBaseURL, pat: mockToken)
        
        let imageURL = URL(string: "https://some-other-site.com/avatar.png")!
        
        var hasAuthHeader = false
        MockURLProtocol.requestHandler = { request in
            hasAuthHeader = request.value(forHTTPHeaderField: "Authorization") != nil
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.mockImageData)
        }
        
        let loader = MemosImageLoader(
            cache: DefaultNetworkImageCache(countLimit: 1),
            session: session,
            auth: mockAuth
        )
        let _ = try await loader.image(from: imageURL)
        
        XCTAssertFalse(hasAuthHeader)
    }
    
    func testCacheUsage() async throws {
        let mockBaseURL = URL(string: "https://memos-test.top:8080")!
        let mockToken = "mock_pat_token_abc"
        let mockAuth = try makeMockAuth(baseURL: mockBaseURL, pat: mockToken)
        
        let imageURL = URL(string: "https://some-other-site.com/cache-test.png")!
        
        var networkRequestCount = 0
        MockURLProtocol.requestHandler = { request in
            networkRequestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.mockImageData)
        }
        
        let loader = MemosImageLoader(
            cache: DefaultNetworkImageCache(countLimit: 10),
            session: session,
            auth: mockAuth
        )
        
        // Load first time (should hit network)
        let image1 = try await loader.image(from: imageURL)
        XCTAssertEqual(networkRequestCount, 1)
        XCTAssertNotNil(image1)
        
        // Load second time (should hit cache, no network request)
        let image2 = try await loader.image(from: imageURL)
        XCTAssertEqual(networkRequestCount, 1)
        XCTAssertNotNil(image2)
    }
}
