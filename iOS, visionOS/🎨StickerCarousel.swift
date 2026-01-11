//
//  🎨StickerCarousel.swift
//  LockInNote
//

import SwiftUI
import PhotosUI

struct 🎨StickerCarousel: View {
    @EnvironmentObject var note: 📝NoteModel
    @State private var imageSelection: PhotosPickerItem?
    @State private var isProcessing = false
    
    let onStickerTapped: (🎨Sticker) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $imageSelection, matching: .images) {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.tint)
                        Text("Add")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 80, height: 80)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .disabled(isProcessing)
                
                ForEach(note.stickerData.stickers) { sticker in
                    if let uiImage = UIImage(data: sticker.imageData) {
                        Button {
                            onStickerTapped(sticker)
                            💥Feedback.light()
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .background(Color(uiColor: .systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(height: 104)
        .background(Color(uiColor: .systemGray6))
        .onChange(of: imageSelection) { _, newSelection in
            loadAndProcessImage(newSelection)
        }
    }
    
    private func loadAndProcessImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isProcessing = true
        
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                guard let data = data,
                      let uiImage = UIImage(data: data) else {
                    isProcessing = false
                    return
                }
                
                processImage(uiImage)
                
            case .failure(let error):
                print("Failed to load image: \(error)")
                isProcessing = false
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        Task {
            let helper = ImageVisionHelper()
            let processedImage = helper.removeBackground(from: image) ?? image
            
            guard let imageData = processedImage.pngData() else {
                await MainActor.run {
                    isProcessing = false
                }
                return
            }
            
            let sticker = 🎨Sticker(imageData: imageData)
            
            await MainActor.run {
                var updatedData = note.stickerData
                updatedData.stickers.append(sticker)
                note.stickerData = updatedData
                
                // Don't save to iCloud - just keep in memory for now
                // TODO: Use local file storage instead of iCloud KVS
                
                isProcessing = false
                imageSelection = nil
                💥Feedback.success()
            }
        }
    }
}
