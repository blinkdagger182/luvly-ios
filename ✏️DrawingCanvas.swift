import SwiftUI
import PencilKit

struct ✏️DrawingCanvas: View {
    @EnvironmentObject var note: 📝NoteModel
    @Binding var isExpanded: Bool
    @State private var canvasView = PKCanvasView()
    @State private var selectedTool: ✏️DrawingTool = .pen
    
    var body: some View {
        VStack(spacing: 0) {
            if self.isExpanded {
                self.topToolbar()
            }
            
            self.canvas()
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
                ✏️DrawingToolbar(
                    selectedTool: self.$selectedTool,
                    canvasView: self.canvasView,
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isExpanded = false
                        }
                        self.saveDrawing()
                        💥Feedback.success()
                    }
                )
            }
        }
        .onAppear {
            self.loadDrawing()
            self.setupCanvas()
        }
    }
}

private extension ✏️DrawingCanvas {
    func canvas() -> some View {
        ✏️CanvasViewRepresentable(
            canvasView: self.$canvasView,
            selectedTool: self.$selectedTool,
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
}

// MARK: - Canvas View Representable

struct ✏️CanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var selectedTool: ✏️DrawingTool
    let isExpanded: Bool
    
    func makeUIView(context: Context) -> PKCanvasView {
        self.canvasView.delegate = context.coordinator
        return self.canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.isUserInteractionEnabled = self.isExpanded
        self.updateTool()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ✏️CanvasViewRepresentable
        
        init(_ parent: ✏️CanvasViewRepresentable) {
            self.parent = parent
        }
    }
}

// MARK: - Drawing Tool Enum

enum ✏️DrawingTool {
    case pen
    case marker
    case eraser
}
