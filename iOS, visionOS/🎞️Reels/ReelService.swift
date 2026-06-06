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

    func deleteReel(id: UUID) async throws {
        var request = URLRequest(url: self.baseURL.appending(path: id.uuidString))
        request.httpMethod = "DELETE"
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
    }

    func upsertSocialProfile(profileID: UUID, handle: String, displayName: String) async throws -> ReelSocialSummary {
        _ = try await self.postSocial(
            action: "profile",
            body: [
                "profile_id": profileID.uuidString,
                "handle": handle,
                "display_name": displayName,
            ] as [String: String],
            responseType: SocialProfileResponse.self
        )
        return try await self.socialSummary(profileID: profileID)
    }

    func socialSummary(profileID: UUID) async throws -> ReelSocialSummary {
        var components = URLComponents(url: self.baseURL.appending(path: "social"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "profile_id", value: profileID.uuidString)]
        guard let url = components?.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelSocialSummary.self, from: data)
    }

    func discoverSocialReels(query: String = "", niche: String = "") async throws -> ReelSocialDiscoverResponse {
        var components = URLComponents(url: self.baseURL.appending(path: "social/discover"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "niche", value: niche),
        ]
        guard let url = components?.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelSocialDiscoverResponse.self, from: data)
    }

    func setBookmark(profileID: UUID, reelID: UUID, isBookmarked: Bool) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "bookmarks",
            body: SocialBookmarkRequest(
                profileID: profileID,
                reelID: reelID,
                isBookmarked: isBookmarked
            ),
            responseType: ReelSocialSummary.self
        )
    }

    func setPublicShare(profileID: UUID, reelID: UUID, isPublic: Bool, nicheTags: [String]) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "public-shares",
            body: SocialPublicShareRequest(
                profileID: profileID,
                reelID: reelID,
                isPublic: isPublic,
                nicheTags: nicheTags
            ),
            responseType: ReelSocialSummary.self
        )
    }

    func createCollection(profileID: UUID, name: String, reelIDs: [UUID], isPublic: Bool) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "collections",
            body: SocialCollectionRequest(
                profileID: profileID,
                name: name,
                reelIDs: reelIDs,
                isPublic: isPublic
            ),
            responseType: ReelSocialSummary.self
        )
    }

    func shareWithFriend(profileID: UUID, reelID: UUID, receiverHandle: String, message: String?) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "friend-shares",
            body: SocialFriendShareRequest(
                profileID: profileID,
                reelID: reelID,
                receiverHandle: receiverHandle,
                message: message
            ),
            responseType: ReelSocialSummary.self
        )
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(self.anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func postSocial<Body: Encodable, Response: Decodable>(
        action: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: self.baseURL.appending(path: "social").appending(path: action))
        request.httpMethod = "POST"
        request.httpBody = try Self.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(Response.self, from: data)
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

struct ReelSocialDiscoverResponse: Decodable, Hashable {
    let reels: [ReelItem]
    let niches: [String]
}

private struct SocialProfileResponse: Decodable {
    let profile: SocialProfile
}

private struct SocialProfile: Decodable {
    let id: UUID
    let handle: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
    }
}

private struct SocialBookmarkRequest: Encodable {
    let profileID: UUID
    let reelID: UUID
    let isBookmarked: Bool

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case reelID = "reel_id"
        case isBookmarked = "is_bookmarked"
    }
}

private struct SocialPublicShareRequest: Encodable {
    let profileID: UUID
    let reelID: UUID
    let isPublic: Bool
    let nicheTags: [String]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case reelID = "reel_id"
        case isPublic = "is_public"
        case nicheTags = "niche_tags"
    }
}

private struct SocialCollectionRequest: Encodable {
    let profileID: UUID
    let name: String
    let reelIDs: [UUID]
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case name
        case reelIDs = "reel_ids"
        case isPublic = "is_public"
    }
}

private struct SocialFriendShareRequest: Encodable {
    let profileID: UUID
    let reelID: UUID
    let receiverHandle: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case reelID = "reel_id"
        case receiverHandle = "receiver_handle"
        case message
    }
}
