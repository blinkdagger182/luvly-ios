//
//  🎨StickerModel.swift
//  LockInNote
//

import SwiftUI

struct 🎨Sticker: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    var position: CGPoint
    var scale: CGFloat
    
    init(id: UUID = UUID(), imageData: Data, position: CGPoint = .zero, scale: CGFloat = 1.0) {
        self.id = id
        self.imageData = imageData
        self.position = position
        self.scale = scale
    }
}

struct 🎨StickerData: Codable {
    var stickers: [🎨Sticker]
    
    init(stickers: [🎨Sticker] = []) {
        self.stickers = stickers
    }
    
    var data: Data {
        get throws {
            try JSONEncoder().encode(self)
        }
    }
    
    init(data: Data) throws {
        self = try JSONDecoder().decode(🎨StickerData.self, from: data)
    }
}
