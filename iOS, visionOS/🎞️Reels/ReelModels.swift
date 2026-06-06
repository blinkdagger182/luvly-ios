import Foundation

struct ReelItem: Identifiable, Codable, Hashable {
    let id: UUID
    let source: String
    let sourceURL: URL
    let creatorUsername: String?
    let creatorDisplayName: String?
    let caption: String?
    let thumbnailURL: URL?
    let durationSeconds: Int?
    let videoURL: URL?
    let mediaItems: [ReelMediaItem]?
    let title: String?
    let category: String?
    let summary: String?
    let status: String
    let errorMessage: String?
    let createdAt: String?
    let social: ReelSocialStats?
    let segments: [ReelSegment]
    let ocrEntries: [ReelOCREntry]?

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case sourceURL = "source_url"
        case creatorUsername = "creator_username"
        case creatorDisplayName = "creator_display_name"
        case caption
        case thumbnailURL = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case videoURL = "video_url"
        case mediaItems = "media_items"
        case title
        case category
        case summary
        case status
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case social
        case segments = "reel_segments"
        case ocrEntries = "reel_ocr_entries"
    }
}

struct ReelSocialStats: Codable, Hashable {
    let nicheTags: [String]
    let shareCount: Int
    let saveCount: Int
    let viewCount: Int
    let sharedAt: String?

    enum CodingKeys: String, CodingKey {
        case nicheTags = "niche_tags"
        case shareCount = "share_count"
        case saveCount = "save_count"
        case viewCount = "view_count"
        case sharedAt = "shared_at"
    }
}

struct ReelSocialSummary: Decodable, Hashable {
    let bookmarkIDs: [UUID]
    let publicReelIDs: [UUID]
    let publicShares: [ReelPublicShare]
    let collections: [ReelSocialCollection]
    let friendShares: [ReelFriendShare]
    let friendships: [ReelFriendship]
    let friends: [ReelFriendship]
    let incomingFriendRequests: [ReelFriendship]
    let outgoingFriendRequests: [ReelFriendship]
    let niches: [String]
    let popularReels: [ReelItem]

    static let empty = ReelSocialSummary(
        bookmarkIDs: [],
        publicReelIDs: [],
        publicShares: [],
        collections: [],
        friendShares: [],
        friendships: [],
        friends: [],
        incomingFriendRequests: [],
        outgoingFriendRequests: [],
        niches: [],
        popularReels: []
    )

    enum CodingKeys: String, CodingKey {
        case bookmarkIDs = "bookmark_ids"
        case publicReelIDs = "public_reel_ids"
        case publicShares = "public_shares"
        case collections
        case friendShares = "friend_shares"
        case friendships
        case friends
        case incomingFriendRequests = "incoming_friend_requests"
        case outgoingFriendRequests = "outgoing_friend_requests"
        case niches
        case popularReels = "popular_reels"
    }
}

struct ReelSocialProfile: Identifiable, Decodable, Hashable {
    let id: UUID
    let handle: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
    }
}

struct ReelFriendship: Identifiable, Decodable, Hashable {
    let id: UUID
    let requesterProfileID: UUID
    let receiverProfileID: UUID
    let status: String
    let otherProfile: ReelSocialProfile?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterProfileID = "requester_profile_id"
        case receiverProfileID = "receiver_profile_id"
        case status
        case otherProfile = "other_profile"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ReelPublicShare: Identifiable, Decodable, Hashable {
    var id: UUID { self.reelID }
    let reelID: UUID
    let nicheTags: [String]
    let shareCount: Int
    let saveCount: Int
    let viewCount: Int
    let sharedAt: String?

    enum CodingKeys: String, CodingKey {
        case reelID = "reel_id"
        case nicheTags = "niche_tags"
        case shareCount = "share_count"
        case saveCount = "save_count"
        case viewCount = "view_count"
        case sharedAt = "shared_at"
    }
}

struct ReelSocialCollection: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let isPublic: Bool
    let shareCount: Int
    let items: [ReelSocialCollectionItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case isPublic = "is_public"
        case shareCount = "share_count"
        case items = "reel_social_collection_items"
    }
}

struct ReelSocialCollectionItem: Decodable, Hashable {
    let reelID: UUID
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case reelID = "reel_id"
        case orderIndex = "order_index"
    }
}

struct ReelFriendShare: Identifiable, Decodable, Hashable {
    let id: UUID
    let senderProfileID: UUID
    let receiverProfileID: UUID?
    let receiverHandle: String?
    let reelID: UUID?
    let collectionID: UUID?
    let message: String?
    let createdAt: String?
    let reel: ReelItem?
    let collection: ReelSocialCollection?

    enum CodingKeys: String, CodingKey {
        case id
        case senderProfileID = "sender_profile_id"
        case receiverProfileID = "receiver_profile_id"
        case receiverHandle = "receiver_handle"
        case reelID = "reel_id"
        case collectionID = "collection_id"
        case message
        case createdAt = "created_at"
        case reel
        case collection
    }
}

struct ReelShareInbox: Decodable, Hashable {
    let shares: [ReelFriendShare]
}

struct ReelFriendState: Decodable, Hashable {
    let friendships: [ReelFriendship]
    let friends: [ReelFriendship]
    let incomingFriendRequests: [ReelFriendship]
    let outgoingFriendRequests: [ReelFriendship]

    enum CodingKeys: String, CodingKey {
        case friendships
        case friends
        case incomingFriendRequests = "incoming_friend_requests"
        case outgoingFriendRequests = "outgoing_friend_requests"
    }
}

struct ReelMediaItem: Codable, Hashable {
    let type: String
    let url: URL
    let thumbnailURL: URL?
    let durationSeconds: Int?
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case type
        case url
        case thumbnailURL = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case orderIndex = "order_index"
    }
}

struct ReelSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let startSeconds: Int
    let endSeconds: Int
    let title: String
    let description: String
    let rawText: String?
    let tags: [String]
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case title
        case description
        case rawText = "raw_text"
        case tags
        case orderIndex = "order_index"
    }
}

struct ReelOCREntry: Identifiable, Codable, Hashable {
    var id = UUID()
    let timestampSeconds: Int
    let text: String
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case timestampSeconds = "timestamp_seconds"
        case text
        case confidence
    }
}
