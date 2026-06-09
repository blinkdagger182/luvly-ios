import Foundation

enum ReelIntentType: String, CaseIterable {
    case recipe
    case workout
    case travel
    case foodGuide = "food_guide"
    case tutorial
    case aiTool = "ai_tool"
    case study
    case beauty
    case fashion
    case tech
    case diy
    case finance
    case business
    case productReview = "product_review"
    case language
    case motivation
    case news
    case general

    var displayName: String {
        switch self {
        case .recipe: return "Recipe"
        case .workout: return "Workout"
        case .travel: return "Travel"
        case .foodGuide: return "Food Guide"
        case .tutorial: return "Tutorial"
        case .aiTool: return "AI Tool"
        case .study: return "Study"
        case .beauty: return "Beauty"
        case .fashion: return "Fashion"
        case .tech: return "Dev"
        case .diy: return "DIY"
        case .finance: return "Finance"
        case .business: return "Business"
        case .productReview: return "Review"
        case .language: return "Language"
        case .motivation: return "Mindset"
        case .news: return "News"
        case .general: return "General"
        }
    }

    var primaryTabName: String {
        switch self {
        case .recipe: return "Recipe"
        case .workout: return "Workout"
        case .travel: return "Places"
        case .foodGuide: return "Guide"
        case .tutorial: return "Guide"
        case .aiTool: return "Guide"
        case .study: return "Notes"
        case .beauty: return "Routine"
        case .fashion: return "Outfit"
        case .tech: return "Dev Steps"
        case .diy: return "Project"
        case .finance: return "Key Points"
        case .business: return "Strategy"
        case .productReview: return "Review"
        case .language: return "Phrases"
        case .motivation: return "Insights"
        case .news: return "Briefing"
        case .general: return "Steps"
        }
    }

    var symbolName: String {
        switch self {
        case .recipe: return "fork.knife"
        case .workout: return "figure.run"
        case .travel: return "airplane"
        case .foodGuide: return "mappin.and.ellipse"
        case .tutorial: return "list.number"
        case .aiTool: return "wand.and.sparkles"
        case .study: return "books.vertical"
        case .beauty: return "sparkles"
        case .fashion: return "bag"
        case .tech: return "chevron.left.forwardslash.chevron.right"
        case .diy: return "hammer"
        case .finance: return "dollarsign.circle"
        case .business: return "chart.line.uptrend.xyaxis"
        case .productReview: return "star.leadinghalf.filled"
        case .language: return "bubble.left.and.bubble.right"
        case .motivation: return "flame"
        case .news: return "newspaper"
        case .general: return "play.rectangle"
        }
    }
}

struct AiTab: Codable, Hashable {
    let id: String
    let label: String
}

struct AiOverviewItem: Codable, Hashable {
    // key-value items (quick_answer, ingredients, key_points, etc.)
    let label: String?
    let value: String?
    let note: String?
    // step items
    let title: String?
    let body: String?
    let timestamp: String?
}

struct AiOverviewSection: Codable, Hashable {
    let id: String
    let tabId: String?
    let type: String?
    let title: String
    let items: [AiOverviewItem]

    enum CodingKeys: String, CodingKey {
        case id, type, title, items
        case tabId = "tab_id"
    }
}

struct AiOverview: Codable, Hashable {
    let type: String
    let title: String
    let summary: String
    let confidence: String?
    let tabs: [AiTab]?
    let sections: [AiOverviewSection]
}

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
    let transcriptSegments: [ReelTranscriptSegment]?
    let reelType: String?
    let dominantSignal: String?
    let aiOverview: AiOverview?

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
        case transcriptSegments = "reel_transcript_segments"
        case reelType = "reel_type"
        case dominantSignal = "dominant_signal"
        case aiOverview = "ai_overview"
    }

    var intentType: ReelIntentType {
        guard let category else { return .general }
        return ReelIntentType(rawValue: category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) ?? .general
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

struct ReelTranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let startSeconds: Double
    let endSeconds: Double
    let text: String
    let isMusicLike: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case text
        case isMusicLike = "is_music_like"
    }
}
