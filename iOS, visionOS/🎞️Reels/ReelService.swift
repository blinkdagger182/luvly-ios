import Foundation

struct ReelService {
    enum ServiceError: LocalizedError {
        case missingConfig
        case invalidResponse
        case backend(String)

        var errorDescription: String? {
            switch self {
                case .missingConfig:
                    "Missing Supabase URL or anon key. Run backend/scripts/generate-ios-reel-config.sh."
                case .invalidResponse:
                    "The backend returned an invalid response."
                case .backend(let message):
                    message
            }
        }
    }

    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    init(session: URLSession = .shared) throws {
        guard let supabaseURL = URL(string: ReelBackendConfig.supabaseURL),
              !ReelBackendConfig.supabaseURL.isEmpty,
              !ReelBackendConfig.supabaseAnonKey.isEmpty else {
            throw ServiceError.missingConfig
        }

        self.baseURL = supabaseURL.appending(path: "functions/v1/reels")
        self.anonKey = ReelBackendConfig.supabaseAnonKey
        self.session = session
    }

    func listReels() async throws -> [ReelItem] {
        var request = URLRequest(url: self.baseURL)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelListResponse.self, from: data).reels
    }

    func importReel(url: URL) async throws -> ReelItem {
        var request = URLRequest(url: self.baseURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["url": url.absoluteString])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelDetailResponse.self, from: data).reel
    }

    func submitOCR(reelID: UUID, entries: [ReelOCREntry]) async throws -> ReelItem {
        var request = URLRequest(url: self.baseURL.appending(path: reelID.uuidString))
        request.httpMethod = "PATCH"
        request.httpBody = try Self.encoder.encode(["entries": entries])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelDetailResponse.self, from: data).reel
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(self.anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder().decode(ReelErrorResponse.self, from: data) {
                throw ServiceError.backend(error.error)
            }
            throw ServiceError.backend("Backend returned HTTP \(httpResponse.statusCode).")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private struct ReelListResponse: Decodable {
    let reels: [ReelItem]
}

private struct ReelDetailResponse: Decodable {
    let reel: ReelItem
}

private struct ReelErrorResponse: Decodable {
    let error: String
}
