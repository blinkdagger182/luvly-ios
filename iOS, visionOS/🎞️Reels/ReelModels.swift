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
    let title: String?
    let category: String?
    let summary: String?
    let status: String
    let errorMessage: String?
    let createdAt: String?
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
        case title
        case category
        case summary
        case status
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case segments = "reel_segments"
        case ocrEntries = "reel_ocr_entries"
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
