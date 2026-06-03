import SwiftUI
import PencilKit

struct 🖊DrawingToolbar: View {
    @Binding var selectedTool: 🖊DrawingTool
    @Binding var selectedColor: Color
    @Binding var showColorPicker: Bool
    let canvasView: PKCanvasView
    let onClose: () -> Void
    
    let availableColors: [Color] = [
        .black, .white, .gray,
        .red, .orange, .yellow,
        .green, .mint, .cyan,
        .blue, .indigo, .purple,
        .pink, .brown
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if showColorPicker {
                self.colorPickerView()
            }
            
            HStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(🖊DrawingTool.allCases, id: \.self) { tool in
                            self.toolButton(tool)
                        }
                    }
                }
                
                Divider()
                    .frame(height: 44)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showColorPicker.toggle()
                    }
                    💥Feedback.light()
                } label: {
                    ZStack {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 32, height: 32)
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }
                }
                .disabled(selectedTool == .eraser || selectedTool == .eraserObject)
                .opacity(selectedTool == .eraser || selectedTool == .eraserObject ? 0.3 : 1.0)
                
                Divider()
                    .frame(height: 44)
                
                Button {
                    self.onClose()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .background(Circle().fill(.tint).frame(width: 44, height: 44))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

private extension 🖊DrawingToolbar {
    func toolButton(_ tool: 🖊DrawingTool) -> some View {
        Button {
            self.selectedTool = tool
            💥Feedback.selection()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(self.selectedTool == tool ? .primary : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(self.selectedTool == tool ? Color(uiColor: .systemGray5) : .clear)
                    )
                
                Text(tool.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    func colorPickerView() -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(availableColors, id: \.self) { color in
                    Button {
                        selectedColor = color
                        💥Feedback.light()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 36, height: 36)
                            
                            if color == .white {
                                Circle()
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 36, height: 36)
                            }
                            
                            if selectedColor == color {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 3)
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            ColorPicker("Custom Color", selection: $selectedColor, supportsOpacity: false)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGray6))
    }
}
