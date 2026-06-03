import SwiftUI
import PencilKit

struct 🖊DrawingCanvas: View {
    @EnvironmentObject var note: 📝NoteModel
    @Binding var isExpanded: Bool
    @State private var canvasView = PKCanvasView()
    @State private var selectedTool: 🖊DrawingTool = .pen
    @State private var selectedColor: Color = .black
    @State private var showColorPicker: Bool = false
    @State private var autoSaveTimer: Timer?
    @State private var placedStickers: [PlacedSticker] = []
    
    func addStickerFromExternal(_ sticker: 🎨Sticker) {
        addStickerToCanvas(sticker)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if self.isExpanded {
                self.topToolbar()
            }
            
            ZStack {
                self.canvas()
                
                ForEach(placedStickers) { placed in
                    if let uiImage = UIImage(data: placed.sticker.imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100 * placed.scale, height: 100 * placed.scale)
                            .position(placed.position)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        updateStickerPosition(id: placed.id, position: value.location)
                                    }
                            )
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        updateStickerScale(id: placed.id, scale: value)
                                    }
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: self.isExpanded ? .infinity : nil)
            .frame(height: self.isExpanded ? nil : 300)
            .aspectRatio(self.isExpanded ? nil : 1, contentMode: .fit)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 2)
            .padding(self.isExpanded ? 0 : 20)
            .onTapGesture {
                if !self.isExpanded {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.isExpanded = true
                    }
                    💥Feedback.light()
                }
            }
            

            
            if self.isExpanded {
                🖊DrawingToolbar(
                    selectedTool: self.$selectedTool,
                    selectedColor: self.$selectedColor,
                    showColorPicker: self.$showColorPicker,
                    canvasView: self.canvasView,
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isExpanded = false
                        }
                        self.saveDrawing()
                        self.saveStickers()
                        💥Feedback.success()
                    }
                )
            }
        }
        .onAppear {
            self.loadDrawing()
            self.loadStickers()
            self.setupCanvas()
            self.startAutoSave()
        }
        .onDisappear {
            self.stopAutoSave()
            self.saveDrawing()
            self.saveStickers()
        }
        .onChange(of: self.isExpanded) { ⓔxpanded in
            if !ⓔxpanded {
                self.saveDrawing()
                self.saveStickers()
            }
        }
    }
}

private extension 🖊DrawingCanvas {
    func canvas() -> some View {
        🖊CanvasViewRepresentable(
            canvasView: self.$canvasView,
            selectedTool: self.$selectedTool,
            selectedColor: self.$selectedColor,
            isExpanded: self.isExpanded
        )
    }
    
    func topToolbar() -> some View {
        HStack {
            Button {
                self.canvasView.undoManager?.undo()
                💥Feedback.light()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .disabled(self.canvasView.undoManager?.canUndo != true)
            
            Button {
                self.canvasView.undoManager?.redo()
                💥Feedback.light()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .disabled(self.canvasView.undoManager?.canRedo != true)
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.isExpanded = false
                }
                self.saveDrawing()
                💥Feedback.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
    
    func setupCanvas() {
        self.canvasView.drawingPolicy = .anyInput
        self.canvasView.backgroundColor = .systemBackground
        self.updateTool()
    }
    
    func updateTool() {
        let uiColor = UIColor(selectedColor)
        
        switch self.selectedTool {
        case .pencil:
            self.canvasView.tool = PKInkingTool(.pencil, color: uiColor, width: 2)
        case .pen:
            self.canvasView.tool = PKInkingTool(.pen, color: uiColor, width: 3)
        case .marker:
            self.canvasView.tool = PKInkingTool(.marker, color: uiColor, width: 20)
        case .highlighter:
            self.canvasView.tool = PKInkingTool(.marker, color: uiColor.withAlphaComponent(0.4), width: 30)
        case .eraser:
            self.canvasView.tool = PKEraserTool(.vector)
        case .eraserObject:
            self.canvasView.tool = PKEraserTool(.bitmap)
        }
    }
    
    func loadDrawing() {
        guard let ⓓrawingData = try? self.note.drawingData.data,
              !ⓓrawingData.isEmpty,
              let ⓓrawing = try? PKDrawing(data: ⓓrawingData) else {
            return
        }
        self.canvasView.drawing = ⓓrawing
    }
    
    func saveDrawing() {
        let ⓓata = self.canvasView.drawing.dataRepresentation()
        let ⓓrawingData = 📝DrawingData(data: ⓓata)
        self.note.save(.drawingData, ⓓrawingData)
    }
    
    func startAutoSave() {
        self.autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.saveDrawing()
        }
    }
    
    func stopAutoSave() {
        self.autoSaveTimer?.invalidate()
        self.autoSaveTimer = nil
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
    
    func addStickerToCanvas(_ sticker: 🎨Sticker) {
        let placed = PlacedSticker(
            id: sticker.id,
            sticker: sticker,
            position: CGPoint(x: 200, y: 200),
            scale: 1.0
        )
        placedStickers.append(placed)
    }
    
    func updateStickerPosition(id: UUID, position: CGPoint) {
        if let index = placedStickers.firstIndex(where: { $0.id == id }) {
            placedStickers[index].position = position
        }
    }
    
    func updateStickerScale(id: UUID, scale: CGFloat) {
        if let index = placedStickers.firstIndex(where: { $0.id == id }) {
            placedStickers[index].scale = scale
        }
    }
}

// MARK: - Canvas View Representable

struct 🖊CanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var selectedTool: 🖊DrawingTool
    @Binding var selectedColor: Color
    let isExpanded: Bool
    
    func makeUIView(context: Context) -> PKCanvasView {
        self.canvasView.delegate = context.coordinator
        self.canvasView.drawingPolicy = .anyInput
        self.canvasView.bouncesZoom = false
        self.canvasView.contentInsetAdjustmentBehavior = .never
        
        return self.canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.isUserInteractionEnabled = self.isExpanded
        uiView.isScrollEnabled = self.isExpanded
        self.updateTool()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateTool() {
        let uiColor = UIColor(selectedColor)
        
        switch self.selectedTool {
        case .pencil:
            self.canvasView.tool = PKInkingTool(.pencil, color: uiColor, width: 2)
        case .pen:
            self.canvasView.tool = PKInkingTool(.pen, color: uiColor, width: 3)
        case .marker:
            self.canvasView.tool = PKInkingTool(.marker, color: uiColor, width: 20)
        case .highlighter:
            self.canvasView.tool = PKInkingTool(.marker, color: uiColor.withAlphaComponent(0.4), width: 30)
        case .eraser:
            self.canvasView.tool = PKEraserTool(.vector)
        case .eraserObject:
            self.canvasView.tool = PKEraserTool(.bitmap)
        }
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: 🖊CanvasViewRepresentable
        
        init(_ parent: 🖊CanvasViewRepresentable) {
            self.parent = parent
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Auto-save will be handled by parent view
        }
    }
}

// MARK: - Drawing Tool Enum

enum 🖊DrawingTool: CaseIterable {
    case pencil
    case pen
    case marker
    case highlighter
    case eraser
    case eraserObject
    
    var icon: String {
        switch self {
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .marker: return "paintbrush.pointed.fill"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser.line.dashed"
        case .eraserObject: return "eraser.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .pencil: return "Pencil"
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .eraserObject: return "Object Eraser"
        }
    }
}

// MARK: - Placed Sticker

struct PlacedSticker: Identifiable {
    let id: UUID
    let sticker: 🎨Sticker
    var position: CGPoint
    var scale: CGFloat
}
