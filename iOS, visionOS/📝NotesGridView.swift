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
        NavigationStack {
            VStack(spacing: 0) {
                🖊FullScreenCanvas(
                    note: self.getNote(ⓕamily),
                    family: ⓕamily
                )
                .frame(maxWidth: 400)
                .portal(item: ⓕamily, .destination)
                .padding(.top, 20)
                .padding(.horizontal, 20)
                
                Spacer()
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

// MARK: - Full Screen Canvas

struct 🖊FullScreenCanvas: View {
    @ObservedObject var note: 📝NoteModel
    let family: 📝NoteFamily
    
    @State private var isLoading = true
    
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
                onReady: {
                    self.isLoading = false
                }
            )
            .opacity(self.isLoading ? 0 : 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
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
    var onReady: (() -> Void)?
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = self.backgroundColor
        canvas.isOpaque = true
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.delegate = context.coordinator
        
        // Lock zoom BEFORE loading drawing
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0
        canvas.zoomScale = 1.0
        canvas.bouncesZoom = false
        canvas.contentOffset = .zero
        
        // Load existing drawing
        if !self.note.drawingData.data.isEmpty,
           let drawing = try? PKDrawing(data: self.note.drawingData.data) {
            canvas.drawing = drawing
            // Force reset immediately after loading
            canvas.zoomScale = 1.0
            canvas.contentOffset = .zero
        }
        
        // Store note reference and onReady callback in coordinator
        context.coordinator.note = self.note
        context.coordinator.onReady = self.onReady
        context.coordinator.startAutoSave(canvas: canvas)
        
        // Signal ready on next run loop (can't update SwiftUI state during makeUIView)
        DispatchQueue.main.async {
            context.coordinator.onReady?()
            context.coordinator.onReady = nil
        }
        
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.backgroundColor = self.backgroundColor
        context.coordinator.note = self.note
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


