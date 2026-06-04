import SwiftUI
import PencilKit
import Portal

struct 📝NotesGridView: View {
    @EnvironmentObject var app: 📱AppModel
    @State private var expandedNote: 📝NoteFamily?
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        PortalContainer {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: self.columns, spacing: 16) {
                        ForEach(📝NoteFamily.allCases) { ⓕamily in
                            self.noteCard(ⓕamily)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Notes")
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .fullScreenCover(item: self.$expandedNote) { ⓕamily in
                self.expandedNoteView(ⓕamily)
            }
            .portalTransition(item: self.$expandedNote) { ⓕamily in
                self.notePreview(ⓕamily)
            }
        }
    }
}

private extension 📝NotesGridView {
    func noteCard(_ ⓕamily: 📝NoteFamily) -> some View {
        VStack(spacing: 8) {
            self.notePreview(ⓕamily)
                .portal(item: ⓕamily, .source)
            
            Text(self.noteTitle(ⓕamily))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .id(ⓕamily.id)
        .contentShape(Rectangle())
        .onTapGesture {
            self.expandedNote = ⓕamily
            💥Feedback.light()
        }
    }
    
    func expandedNoteView(_ ⓕamily: 📝NoteFamily) -> some View {
        let note = self.getNote(ⓕamily)
        
        return NavigationStack {
            FullScreenCanvasContainer(note: note, family: ⓕamily) {
                self.expandedNote = nil
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(self.noteTitle(ⓕamily))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        self.expandedNote = nil
                        💥Feedback.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        self.app.sheet = .customize(ⓕamily)
                        💥Feedback.selection()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
    }
    
    func getNote(_ ⓕamily: 📝NoteFamily) -> 📝NoteModel {
        switch ⓕamily {
            case .primary: self.app.primaryNote
            case .secondary: self.app.secondaryNote
            case .tertiary: self.app.tertiaryNote
        }
    }
    

    func notePreview(_ ⓕamily: 📝NoteFamily) -> some View {
        let note = self.getNote(ⓕamily)
        let isExpanding = self.expandedNote == ⓕamily
        
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(self.backgroundColor(ⓕamily))
            
            // Show spinner when expanding, otherwise show content
            if isExpanding {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.secondary)
            } else if !note.drawingData.data.isEmpty,
                      let ⓓrawing = try? PKDrawing(data: note.drawingData.data) {
                🖊DrawingPreview(
                    drawing: ⓓrawing,
                    dataHash: note.drawingData.data.hashValue
                )
                .padding(8)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(radius: 2)
    }
    
    func backgroundColor(_ ⓕamily: 📝NoteFamily) -> Color {
        switch ⓕamily {
            case .primary:
                Color(uiColor: .systemBackground)
            case .secondary:
                Color.teal
            case .tertiary:
                Color.orange
        }
    }
    
    func noteTitle(_ ⓕamily: 📝NoteFamily) -> String {
        switch ⓕamily {
            case .primary:
                self.app.primaryNote.title
            case .secondary:
                self.app.secondaryNote.title
            case .tertiary:
                self.app.tertiaryNote.title
        }
    }
    
}

// MARK: - Full Screen Canvas Container

struct FullScreenCanvasContainer: View {
    @ObservedObject var note: 📝NoteModel
    let family: 📝NoteFamily
    let onClose: () -> Void
    
    @State private var selectedTool: 🖊DrawingTool = .pen
    @State private var selectedColor: Color = .black
    @State private var showColorPicker: Bool = false
    @State private var canvasView = PKCanvasView()
    
    var body: some View {
        VStack(spacing: 0) {
            🖊FullScreenCanvas(
                note: note,
                family: family,
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                canvasView: $canvasView
            )
            .frame(maxWidth: 400)
            .portal(item: family, .destination)
            .padding(.top, 20)
            .padding(.horizontal, 20)
            
            🎨StickerCarousel { sticker in
                // Sticker tapped - it's already in the note's stickerData
                💥Feedback.light()
            }
            .environmentObject(note)
            .frame(maxWidth: 400)
            .padding(.horizontal, 20)
            
            🖊DrawingToolbar(
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                showColorPicker: $showColorPicker,
                canvasView: canvasView,
                onClose: {
                    onClose()
                    💥Feedback.success()
                }
            )
            .frame(maxWidth: 400)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            Spacer()
        }
    }
}

// MARK: - Full Screen Canvas

struct 🖊FullScreenCanvas: View {
    @ObservedObject var note: 📝NoteModel
    let family: 📝NoteFamily
    @Binding var selectedTool: 🖊DrawingTool
    @Binding var selectedColor: Color
    @Binding var canvasView: PKCanvasView
    
    @State private var isLoading = true
    @State private var placedStickers: [PlacedSticker] = []
    @State private var selectedStickerId: UUID?
    @State private var stickerBaseScale: [UUID: CGFloat] = [:]
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .fill(self.backgroundColor)
            
            // Loading spinner
            if self.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.secondary)
            }
            
            // Canvas - always present but hidden until ready
            🖊CanvasRepresentable(
                note: self.note,
                backgroundColor: UIColor(self.backgroundColor),
                selectedTool: self.$selectedTool,
                selectedColor: self.$selectedColor,
                canvasView: self.$canvasView,
                onReady: {
                    self.isLoading = false
                }
            )
            .opacity(self.isLoading ? 0 : 1)
            
            // Stickers overlay
            ForEach(placedStickers) { placed in
                if let uiImage = UIImage(data: placed.sticker.imageData) {
                    StickerView(
                        image: uiImage,
                        placed: placed,
                        isSelected: selectedStickerId == placed.id,
                        baseScale: stickerBaseScale[placed.id],
                        onSelect: {
                            if selectedStickerId == placed.id {
                                selectedStickerId = nil
                            } else {
                                selectedStickerId = placed.id
                            }
                            💥Feedback.selection()
                        },
                        onDelete: {
                            deleteSticker(id: placed.id)
                            💥Feedback.light()
                        },
                        onDragChanged: { position in
                            selectedStickerId = placed.id
                            updateStickerPosition(id: placed.id, position: position)
                        },
                        onDragEnded: {
                            saveStickers()
                        },
                        onScaleChanged: { magnification in
                            selectedStickerId = placed.id
                            if stickerBaseScale[placed.id] == nil {
                                stickerBaseScale[placed.id] = placed.scale
                            }
                            if let baseScale = stickerBaseScale[placed.id] {
                                let newScale = baseScale * magnification
                                updateStickerScale(id: placed.id, scale: newScale)
                            }
                        },
                        onScaleEnded: { magnification in
                            if let baseScale = stickerBaseScale[placed.id] {
                                let newScale = baseScale * magnification
                                commitStickerScale(id: placed.id, scale: newScale)
                            }
                            stickerBaseScale[placed.id] = nil
                        }
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect sticker when tapping canvas background
            selectedStickerId = nil
        }
        .onAppear {
            loadStickers()
        }
        .onChange(of: note.stickerData.stickers.count) { _ in
            refreshStickers()
        }
    }
    
    func loadStickers() {
        placedStickers = note.stickerData.stickers.map { sticker in
            PlacedSticker(
                id: sticker.id,
                sticker: sticker,
                position: sticker.position == .zero ? CGPoint(x: 200, y: 200) : sticker.position,
                scale: sticker.scale
            )
        }
    }
    
    func refreshStickers() {
        loadStickers()
    }
    
    func updateStickerPosition(id: UUID, position: CGPoint) {
        if let index = placedStickers.firstIndex(where: { $0.id == id }) {
            placedStickers[index].position = position
        }
    }
    
    func updateStickerScale(id: UUID, scale: CGFloat) {
        if let index = placedStickers.firstIndex(where: { $0.id == id }) {
            let clampedScale = max(0.3, min(scale, 5.0))
            placedStickers[index].scale = clampedScale
        }
    }
    
    func commitStickerScale(id: UUID, scale: CGFloat) {
        if let index = placedStickers.firstIndex(where: { $0.id == id }) {
            let clampedScale = max(0.3, min(scale, 5.0))
            placedStickers[index].scale = clampedScale
            saveStickers()
        }
    }
    
    func deleteSticker(id: UUID) {
        // Remove from local state
        placedStickers.removeAll { $0.id == id }
        
        // Remove from note's sticker data
        var updatedStickers = note.stickerData.stickers
        updatedStickers.removeAll { $0.id == id }
        let stickerData = 🎨StickerData(stickers: updatedStickers)
        note.stickerData = stickerData
        note.save(.stickerData, stickerData)
        
        // Clear selection
        selectedStickerId = nil
    }
    
    func saveStickers() {
        var updatedStickers = note.stickerData.stickers
        for placed in placedStickers {
            if let index = updatedStickers.firstIndex(where: { $0.id == placed.id }) {
                updatedStickers[index].position = placed.position
                updatedStickers[index].scale = placed.scale
            }
        }
        let stickerData = 🎨StickerData(stickers: updatedStickers)
        note.save(.stickerData, stickerData)
    }
    
    private var backgroundColor: Color {
        switch self.family {
            case .primary: Color(uiColor: .systemBackground)
            case .secondary: Color.teal
            case .tertiary: Color.orange
        }
    }
}

// MARK: - Canvas Representable

struct 🖊CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var note: 📝NoteModel
    let backgroundColor: UIColor
    @Binding var selectedTool: 🖊DrawingTool
    @Binding var selectedColor: Color
    @Binding var canvasView: PKCanvasView
    var onReady: (() -> Void)?
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = self.backgroundColor
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        
        // Lock zoom BEFORE loading drawing
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.zoomScale = 1.0
        canvasView.bouncesZoom = false
        canvasView.contentOffset = .zero
        
        // Set initial tool
        updateTool()
        
        // Load existing drawing
        if !self.note.drawingData.data.isEmpty,
           let drawing = try? PKDrawing(data: self.note.drawingData.data) {
            canvasView.drawing = drawing
            // Force reset immediately after loading
            canvasView.zoomScale = 1.0
            canvasView.contentOffset = .zero
        }
        
        // Store note reference and onReady callback in coordinator
        context.coordinator.note = self.note
        context.coordinator.onReady = self.onReady
        context.coordinator.startAutoSave(canvas: canvasView)
        
        // Signal ready on next run loop (can't update SwiftUI state during makeUIView)
        DispatchQueue.main.async {
            context.coordinator.onReady?()
            context.coordinator.onReady = nil
        }
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.backgroundColor = self.backgroundColor
        context.coordinator.note = self.note
        updateTool()
    }
    
    private func updateTool() {
        let uiColor = UIColor(selectedColor)
        
        switch selectedTool {
        case .pencil:
            canvasView.tool = PKInkingTool(.pencil, color: uiColor, width: 2)
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: uiColor, width: 3)
        case .marker:
            canvasView.tool = PKInkingTool(.marker, color: uiColor, width: 20)
        case .highlighter:
            canvasView.tool = PKInkingTool(.marker, color: uiColor.withAlphaComponent(0.4), width: 30)
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
        case .eraserObject:
            canvasView.tool = PKEraserTool(.bitmap)
        }
    }
    
    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.stopAutoSave()
        coordinator.saveDrawing(from: uiView)
        💾ICloud.synchronize()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var note: 📝NoteModel?
        var onReady: (() -> Void)?
        private var autoSaveTimer: Timer?
        private weak var canvasRef: PKCanvasView?
        
        func startAutoSave(canvas: PKCanvasView) {
            self.canvasRef = canvas
            self.autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self, let canvas = self.canvasRef else { return }
                self.saveDrawing(from: canvas)
            }
        }
        
        func stopAutoSave() {
            self.autoSaveTimer?.invalidate()
            self.autoSaveTimer = nil
        }
        
        func saveDrawing(from canvas: PKCanvasView) {
            guard let note = self.note else { return }
            let data = canvas.drawing.dataRepresentation()
            let drawingData = 📝DrawingData(data: data)
            note.drawingData = drawingData
            note.save(.drawingData, drawingData)
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            self.saveDrawing(from: canvasView)
        }
        
        deinit {
            self.stopAutoSave()
        }
    }
}

// MARK: - Drawing Preview

struct 🖊DrawingPreview: View {
    let drawing: PKDrawing
    let drawingDataHash: Int // Used to detect changes
    
    @State private var cachedImage: UIImage?
    @State private var lastHash: Int = 0
    
    init(drawing: PKDrawing, dataHash: Int) {
        self.drawing = drawing
        self.drawingDataHash = dataHash
    }
    
    var body: some View {
        GeometryReader { ⓖeometry in
            Group {
                if let ⓘmage = self.cachedImage, self.lastHash == self.drawingDataHash {
                    Image(uiImage: ⓘmage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                self.generateImage(size: ⓖeometry.size)
            }
            .onChange(of: self.drawingDataHash) {
                self.generateImage(size: ⓖeometry.size)
            }
        }
    }
    
    private func generateImage(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        
        let currentHash = self.drawingDataHash
        DispatchQueue.global(qos: .userInitiated).async {
            let ⓘmage = self.drawing.image(
                from: self.drawing.bounds,
                scale: UIScreen.main.scale
            ).resized(to: size)
            
            DispatchQueue.main.async {
                self.cachedImage = ⓘmage
                self.lastHash = currentHash
            }
        }
    }
}

private extension UIImage {
    func resized(to ⓢize: CGSize) -> UIImage? {
        guard ⓢize.width > 0, ⓢize.height > 0 else { return nil }
        
        let ⓡenderer = UIGraphicsImageRenderer(size: ⓢize)
        return ⓡenderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: ⓢize))
        }
    }
}



// MARK: - Sticker View

struct StickerView: View {
    let image: UIImage
    let placed: PlacedSticker
    let isSelected: Bool
    let baseScale: CGFloat?
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onScaleEnded: (CGFloat) -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            stickerImage
            
            if isSelected {
                deleteButton
            }
        }
        .position(placed.position)
        .gesture(dragGesture)
        .gesture(magnificationGesture)
        .onTapGesture(perform: onSelect)
    }
    
    private var stickerImage: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 100 * placed.scale, height: 100 * placed.scale)
            .background(whiteOutline)
    }
    
    private var whiteOutline: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 100 * placed.scale + 6, height: 100 * placed.scale + 6)
            .blur(radius: 1)
            .colorMultiply(.white)
            .opacity(0.9)
    }
    
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(.red)
                        .frame(width: 24, height: 24)
                )
                .shadow(radius: 2)
        }
        .offset(x: 12, y: -12)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                onDragChanged(value.location)
            }
            .onEnded { _ in
                onDragEnded()
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.0)
            .onChanged { value in
                onScaleChanged(value)
            }
            .onEnded { value in
                onScaleEnded(value) 
            }
    }
}
