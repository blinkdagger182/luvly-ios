import SwiftUI
import PencilKit

struct 🖊DrawingToolbar: View {
    @Binding var selectedTool: 🖊DrawingTool
    let canvasView: PKCanvasView
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            self.toolButton(.pen, icon: "pencil.tip")
            self.toolButton(.marker, icon: "highlighter")
            self.toolButton(.eraser, icon: "eraser.fill")
            
            Spacer()
            
            Button {
                self.onClose()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .background(Circle().fill(.tint).frame(width: 50, height: 50))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(uiColor: .systemBackground))
    }
}

private extension 🖊DrawingToolbar {
    func toolButton(_ ⓣool: 🖊DrawingTool, icon: String) -> some View {
        Button {
            self.selectedTool = ⓣool
            💥Feedback.selection()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(self.selectedTool == ⓣool ? .primary : .secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(self.selectedTool == ⓣool ? Color(uiColor: .systemGray5) : .clear)
                )
        }
    }
}
