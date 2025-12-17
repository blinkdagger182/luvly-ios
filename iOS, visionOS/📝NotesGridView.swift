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
                .frame(height: 300)
                .portal(item: ⓕamily, .destination)
                .padding(.top, 20)
                
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
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(self.backgroundColor(ⓕamily))
            
            if let ⓓrawing = self.loadDrawing(ⓕamily) {
                🖊DrawingPreview(drawing: ⓓrawing)
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
    
    func loadDrawing(_ ⓕamily: 📝NoteFamily) -> PKDrawing? {
        let ⓝote: 📝NoteModel
        switch ⓕamily {
            case .primary:
                ⓝote = self.app.primaryNote
            case .secondary:
                ⓝote = self.app.secondaryNote
            case .tertiary:
                ⓝote = self.app.tertiaryNote
        }
        
        guard !ⓝote.drawingData.data.isEmpty,
              let ⓓrawing = try? PKDrawing(data: ⓝote.drawingData.data) else {
            return nil
        }
        return ⓓrawing
    }
}

// MARK: - Full Screen Canvas

struct 🖊FullScreenCanvas: View {
    @ObservedObject var note: 📝NoteModel
    let family: 📝NoteFamily
    
    @State private var canvasView = PKCanvasView()
    @State private var selectedTool: 🖊DrawingTool = .pen
    @State private var autoSaveTimer: Timer?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(self.backgroundColor)
            
            🖊CanvasViewRepresentable(
                canvasView: self.$canvasView,
                selectedTool: self.$selectedTool,
                isExpanded: true
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(radius: 2)
        .onAppear {
            self.loadDrawing()
            self.setupCanvas()
            self.startAutoSave()
        }
        .onDisappear {
            self.stopAutoSave()
            self.saveDrawing()
        }
    }
    
    private var backgroundColor: Color {
        switch self.family {
            case .primary: Color(uiColor: .systemBackground)
            case .secondary: Color.teal
            case .tertiary: Color.orange
        }
    }
    
    private func setupCanvas() {
        self.canvasView.drawingPolicy = .anyInput
        self.canvasView.backgroundColor = UIColor(self.backgroundColor)
        self.canvasView.isOpaque = false
        self.canvasView.contentInsetAdjustmentBehavior = .never
        self.canvasView.minimumZoomScale = 1.0
        self.canvasView.maximumZoomScale = 1.0
        self.canvasView.zoomScale = 1.0
        self.updateTool()
    }
    
    private func updateTool() {
        switch self.selectedTool {
            case .pen:
                self.canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
            case .marker:
                self.canvasView.tool = PKInkingTool(.marker, color: .black, width: 15)
            case .eraser:
                self.canvasView.tool = PKEraserTool(.vector)
        }
    }
    
    private func loadDrawing() {
        guard let ⓓrawingData = try? self.note.drawingData.data,
              !ⓓrawingData.isEmpty,
              let ⓓrawing = try? PKDrawing(data: ⓓrawingData) else {
            return
        }
        self.canvasView.drawing = ⓓrawing
    }
    
    private func saveDrawing() {
        let ⓓata = self.canvasView.drawing.dataRepresentation()
        let ⓓrawingData = 📝DrawingData(data: ⓓata)
        self.note.save(.drawingData, ⓓrawingData)
    }
    
    private func startAutoSave() {
        self.autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.saveDrawing()
        }
    }
    
    private func stopAutoSave() {
        self.autoSaveTimer?.invalidate()
        self.autoSaveTimer = nil
    }
}

// MARK: - Drawing Preview

struct 🖊DrawingPreview: View {
    let drawing: PKDrawing
    @State private var cachedImage: UIImage?
    
    var body: some View {
        GeometryReader { ⓖeometry in
            Group {
                if let ⓘmage = self.cachedImage {
                    Image(uiImage: ⓘmage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                        .onAppear {
                            self.generateImage(size: ⓖeometry.size)
                        }
                }
            }
        }
    }
    
    private func generateImage(size: CGSize) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ⓘmage = self.drawing.image(
                from: self.drawing.bounds,
                scale: UIScreen.main.scale
            ).resized(to: size)
            
            DispatchQueue.main.async {
                self.cachedImage = ⓘmage
            }
        }
    }
}

private extension UIImage {
    func resized(to ⓢize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(ⓢize, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        self.draw(in: CGRect(origin: .zero, size: ⓢize))
        return UIGraphicsGetCurrentContext()?.makeImage().flatMap { UIImage(cgImage: $0) }
    }
}


