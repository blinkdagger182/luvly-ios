import Foundation

struct ReelService {
    enum ServiceError: LocalizedError {
        case missingConfig
        case invalidResponse
        case backend(String)

        var errorDescription: String? {
            switch self {
                case .missingConfig:
                    "Could not connect to Reelplay servers. Please try again later."
                case .invalidResponse:
                    "Something went wrong on our end. Please try again."
                case .backend(let message):
                    Self.friendlyMessage(for: message)
            }
        }

        private static func friendlyMessage(for raw: String) -> String {
            let lower = raw.lowercased()
            if lower.contains("pgrst204") || lower.contains("no content") {
                return "Something went wrong while saving. Please try again."
            }
            if lower.contains("pgrst116") || lower.contains("contains 0 rows") {
                return "That reel could not be found. It may have been deleted."
            }
            if lower.contains("pgrst301") || lower.contains("jwt") || lower.contains("unauthorized") {
                return "Your session has expired. Please restart the app."
            }
            if lower.contains("tiktok videos over") || lower.contains("not supported") {
                return raw
            }
            if lower.contains("timeout") || lower.contains("timed out") {
                return "Processing took too long. Keep the app open and try again."
            }
            if lower.contains("rate limit") || lower.contains("429") || lower.contains("too many") {
                return "Reelplay is busy right now. Please wait a moment and try again."
            }
            if lower.contains("network") || lower.contains("offline") || lower.contains("no internet") {
                return "No internet connection. Check your connection and try again."
            }
            if lower.contains("http 5") || lower.contains("500") || lower.contains("503") {
                return "Reelplay servers are having an issue. Please try again in a moment."
            }
            if lower.contains("invalid url") || lower.contains("unsupported") {
                return "That link isn't supported. Try Instagram Reels or TikTok videos."
            }
            return "Something went wrong. Please try again."
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

    func listProfileLibrary(profileID: UUID, limit: Int = 30) async throws -> [ReelItem] {
        var components = URLComponents(url: self.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "profile_id", value: profileID.uuidString),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components?.url ?? self.baseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelListResponse.self, from: data).reels
    }

    func reel(id: UUID) async throws -> ReelItem {
        var request = URLRequest(url: self.baseURL.appending(path: id.uuidString))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelDetailResponse.self, from: data).reel
    }

    func importReel(url: URL, profileID: UUID) async throws -> ReelItem {
        var request = URLRequest(url: self.baseURL, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "url": url.absoluteString,
            "profile_id": profileID.uuidString,
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelDetailResponse.self, from: data).reel
    }

    func uploadVideoToStorage(localURL: URL, fileName: String) async throws -> URL {
        let supabaseURL = URL(string: ReelBackendConfig.supabaseURL)!
        let uploadURL = supabaseURL
            .appending(path: "storage/v1/object")
            .appending(path: "reel-videos")
            .appending(path: "gallery/\(fileName)")

        let videoData = try Data(contentsOf: localURL)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(self.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = videoData

        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.backend("Video upload failed")
        }
        _ = data

        let publicURL = supabaseURL
            .appending(path: "storage/v1/object/public")
            .appending(path: "reel-videos")
            .appending(path: "gallery/\(fileName)")
        return publicURL
    }

    func importGalleryReel(videoURL: URL, title: String, durationSeconds: Int?, profileID: UUID) async throws -> ReelItem {
        struct Body: Encodable {
            let profileID: UUID
            let videoURL: String
            let title: String
            let durationSeconds: Int?
            enum CodingKeys: String, CodingKey {
                case profileID = "profile_id"
                case videoURL = "video_url"
                case title
                case durationSeconds = "duration_seconds"
            }
        }
        var request = URLRequest(url: self.baseURL.appending(path: "gallery"), timeoutInterval: 300)
        request.httpMethod = "POST"
        request.httpBody = try Self.encoder.encode(Body(
            profileID: profileID,
            videoURL: videoURL.absoluteString,
            title: title,
            durationSeconds: durationSeconds
        ))
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

    func removeFromLibrary(id: UUID, profileID: UUID) async throws {
        var components = URLComponents(url: self.baseURL.appending(path: id.uuidString), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "profile_id", value: profileID.uuidString)]
        var request = URLRequest(url: components?.url ?? self.baseURL.appending(path: id.uuidString))
        request.httpMethod = "DELETE"
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
    }

    func upsertSocialProfile(profileID: UUID, handle: String, displayName: String) async throws -> ReelSocialProfile {
        try await self.postSocial(
            action: "profile",
            body: [
                "profile_id": profileID.uuidString,
                "handle": handle,
                "display_name": displayName,
            ] as [String: String],
            responseType: SocialProfileResponse.self
        ).profile
    }

    func socialProfile(profileID: UUID) async throws -> ReelSocialProfile {
        var components = URLComponents(url: self.baseURL.appending(path: "social/profile"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "profile_id", value: profileID.uuidString)]
        guard let url = components?.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(SocialProfileResponse.self, from: data).profile
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

    func discoverSocialReels(query: String = "", niche: String = "", limit: Int = 30) async throws -> ReelSocialDiscoverResponse {
        var components = URLComponents(url: self.baseURL.appending(path: "social/discover"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "niche", value: niche),
            URLQueryItem(name: "limit", value: String(limit)),
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
                collectionID: nil,
                receiverHandle: receiverHandle,
                message: message
            ),
            responseType: ReelSocialSummary.self
        )
    }

    func deleteCollection(profileID: UUID, collectionID: UUID) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "collections-delete",
            body: SocialCollectionMutationRequest(profileID: profileID, collectionID: collectionID, name: nil),
            responseType: ReelSocialSummary.self
        )
    }

    func renameCollection(profileID: UUID, collectionID: UUID, name: String) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "collections-rename",
            body: SocialCollectionMutationRequest(profileID: profileID, collectionID: collectionID, name: name),
            responseType: ReelSocialSummary.self
        )
    }

    func shareCollectionWithFriend(profileID: UUID, collectionID: UUID, receiverHandle: String, message: String?) async throws -> ReelSocialSummary {
        try await self.postSocial(
            action: "friend-shares",
            body: SocialFriendShareRequest(
                profileID: profileID,
                reelID: nil,
                collectionID: collectionID,
                receiverHandle: receiverHandle,
                message: message
            ),
            responseType: ReelSocialSummary.self
        )
    }

    func friendState(profileID: UUID) async throws -> ReelFriendState {
        var components = URLComponents(url: self.baseURL.appending(path: "social/friends"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "profile_id", value: profileID.uuidString)]
        guard let url = components?.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelFriendState.self, from: data)
    }

    func shareInbox(profileID: UUID) async throws -> ReelShareInbox {
        var components = URLComponents(url: self.baseURL.appending(path: "social/inbox"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "profile_id", value: profileID.uuidString)]
        guard let url = components?.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        self.authorize(&request)

        let (data, response) = try await self.session.data(for: request)
        try self.validate(response: response, data: data)
        return try Self.decoder.decode(ReelShareInbox.self, from: data)
    }

    func requestFriend(profileID: UUID, receiverHandle: String) async throws -> ReelFriendState {
        try await self.postSocial(
            action: "friends",
            body: SocialFriendRequest(profileID: profileID, receiverHandle: receiverHandle),
            responseType: ReelFriendState.self
        )
    }

    func respondToFriendRequest(profileID: UUID, friendshipID: UUID, accept: Bool) async throws -> ReelFriendState {
        try await self.postSocial(
            action: "friend-response",
            body: SocialFriendResponseRequest(
                profileID: profileID,
                friendshipID: friendshipID,
                response: accept ? "accepted" : "declined"
            ),
            responseType: ReelFriendState.self
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
    let profile: ReelSocialProfile
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

private struct SocialCollectionMutationRequest: Encodable {
    let profileID: UUID
    let collectionID: UUID
    let name: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case collectionID = "collection_id"
        case name
    }
}

private struct SocialFriendShareRequest: Encodable {
    let profileID: UUID
    let reelID: UUID?
    let collectionID: UUID?
    let receiverHandle: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case reelID = "reel_id"
        case collectionID = "collection_id"
        case receiverHandle = "receiver_handle"
        case message
    }
}

private struct SocialFriendRequest: Encodable {
    let profileID: UUID
    let receiverHandle: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case receiverHandle = "receiver_handle"
    }
}

private struct SocialFriendResponseRequest: Encodable {
    let profileID: UUID
    let friendshipID: UUID
    let response: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case friendshipID = "friendship_id"
        case response
    }
}
