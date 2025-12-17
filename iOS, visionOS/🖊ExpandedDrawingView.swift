import SwiftUI
import PencilKit

struct 🖊ExpandedDrawingView: View {
    @ObservedObject var note: 📝NoteModel
    let onClose: () -> Void
    
    @State private var canvasView = PKCanvasView()
    @State private var selectedTool: 🖊DrawingTool = .pen
    @State private var autoSaveTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            🖊CanvasViewRepresentable(
                canvasView: self.$canvasView,
                selectedTool: self.$selectedTool,
                isExpanded: true
            )
            
            🖊DrawingToolbar(
                selectedTool: self.$selectedTool,
                canvasView: self.canvasView,
                onClose: {
                    self.saveDrawing()
                    self.onClose()
                    💥Feedback.success()
                }
            )
        }
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
}

private extension 🖊ExpandedDrawingView {
    func setupCanvas() {
        self.canvasView.drawingPolicy = .anyInput
        self.canvasView.backgroundColor = .systemBackground
        self.updateTool()
    }
    
    func updateTool() {
        switch self.selectedTool {
            case .pen:
                self.canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
            case .marker:
                self.canvasView.tool = PKInkingTool(.marker, color: .black, width: 15)
            case .eraser:
                self.canvasView.tool = PKEraserTool(.vector)
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
}
