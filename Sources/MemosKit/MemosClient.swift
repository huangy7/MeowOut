import Foundation

public class MemosClient: @unchecked Sendable {
    public static let shared = MemosClient()

    private let session: URLSession
    private let auth: MemosAuth
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(session: URLSession = .shared, auth: MemosAuth = .shared) {
        self.session = session
        self.auth = auth
        self.decoder = MemosDateCoding.makeDecoder()
        self.encoder = MemosDateCoding.makeEncoder()
    }

    public var isConfigured: Bool { auth.isConfigured }

    // MARK: - Auth Endpoints

    public func verifyConnection() async throws -> InstanceProfile {
        try await get(path: "/api/v1/instance/profile")
    }

    public func getCurrentUser() async throws -> User {
        let response: GetCurrentUserResponse = try await get(path: "/api/v1/auth/me")
        return response.user
    }

    // MARK: - Memo Endpoints

    public func createMemo(
        content: String,
        visibility: MemoVisibility,
        attachments: [Attachment]? = nil
    ) async throws -> Memo {
        let body = CreateMemoBody(content: content, visibility: visibility, attachments: attachments)
        return try await post(path: "/api/v1/memos", body: body)
    }

    public func listMemos(
        state: MemoState = .normal, filter: String? = nil,
        pageSize: Int = 20, pageToken: String? = nil
    ) async throws -> ListMemosResponse {
        var queryItems = [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "pinned desc, create_time desc")
        ]
        if let filter { queryItems.append(URLQueryItem(name: "filter", value: filter)) }
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get(path: "/api/v1/memos", queryItems: queryItems)
    }

    public func updateMemo(
        name: String, content: String? = nil, visibility: MemoVisibility? = nil,
        state: MemoState? = nil, pinned: Bool? = nil, attachments: [Attachment]? = nil,
        updateMask: [String]
    ) async throws -> Memo {
        let body = UpdateMemoBody(name: name, content: content, visibility: visibility,
                                  state: state, pinned: pinned, attachments: attachments)
        return try await patch(
            path: "/api/v1/\(name)", body: body,
            queryItems: [URLQueryItem(name: "updateMask", value: updateMask.joined(separator: ","))])
    }

    public func deleteMemo(name: String) async throws {
        try await delete(path: "/api/v1/\(name)")
    }

    // MARK: - User Endpoints

    public func getUserStats(userName: String) async throws -> UserStats {
        try await get(path: "/api/v1/\(userName):getStats")
    }

    // MARK: - Attachment Endpoints

    private struct CreateAttachmentBody: Encodable {
        let filename: String
        let content: String // Base64 encoded bytes
        let type: String    // MIME type
    }

    public func uploadAttachment(
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> Attachment {
        let base64String = data.base64EncodedString()
        let body = CreateAttachmentBody(filename: filename, content: base64String, type: mimeType)
        let response: Attachment = try await post(path: "/api/v1/attachments", body: body)
        return response
    }

    private struct ListAttachmentsResponse: Decodable {
        let attachments: [Attachment]?
    }

    public func listAllAttachments() async throws -> [Attachment] {
        do {
            let response: ListAttachmentsResponse = try await get(
                path: "/api/v1/attachments",
                queryItems: [
                    URLQueryItem(name: "pageSize", value: "200"),
                    URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
                ]
            )
            return response.attachments ?? []
        } catch MemosError.serverError(let statusCode, _) where statusCode == 404 {
            let memosResponse = try await listMemos(state: .normal, pageSize: 100)
            let archivedResponse = try? await listMemos(state: .archived, pageSize: 100)
            
            var allMemos = memosResponse.memos
            if let archived = archivedResponse?.memos {
                allMemos.append(contentsOf: archived)
            }
            
            var seen = Set<String>()
            var list: [Attachment] = []
            for memo in allMemos {
                if let attachments = memo.attachments {
                    for att in attachments {
                        if !seen.contains(att.name) {
                            seen.insert(att.name)
                            list.append(att)
                        }
                    }
                }
            }
            return list
        }
    }

    // MARK: - HTTP Primitives

    private func makeRequest(path: String, method: String,
                             queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard let baseURL = auth.baseURL, let pat = auth.pat else {
            throw MemosError.notConfigured
        }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MemosError.networkError(NSError(domain: "MemosClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        if let queryItems, !queryItems.isEmpty { components.queryItems = queryItems }
        guard let finalURL = components.url else {
            throw MemosError.networkError(NSError(domain: "MemosClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"]))
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    private func patch<T: Decodable, B: Encodable>(
        path: String, body: B, queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var request = try makeRequest(path: path, method: "PATCH", queryItems: queryItems)
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    private func delete(path: String) async throws {
        let request = try makeRequest(path: path, method: "DELETE")
        let (data, response) = try await perform(request)
        try checkStatus(response, data: data)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await perform(request)
        try checkStatus(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MemosError.decodingError(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MemosError.networkError(
                    NSError(domain: "MemosClient", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Not an HTTP response"]))
            }
            return (data, httpResponse)
        } catch let error as MemosError {
            throw error
        } catch {
            throw MemosError.networkError(error)
        }
    }

    private struct ErrorResponse: Decodable {
        let message: String
    }

    private func checkStatus(_ response: HTTPURLResponse, data: Data?) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw MemosError.unauthorized
        default:
            var errorMessage = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            if let data = data,
               let errorResp = try? decoder.decode(ErrorResponse.self, from: data),
               !errorResp.message.isEmpty {
                errorMessage = errorResp.message
            }
            throw MemosError.serverError(statusCode: response.statusCode,
                                         message: errorMessage)
        }
    }
}
