import SwiftUI

struct 📝NoteTab: View {
    @EnvironmentObject var app: 📱AppModel
    @EnvironmentObject var note: 📝NoteModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isDrawingExpanded: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                self.backgroundColor()
                
                if self.isDrawingExpanded {
                    🖊DrawingCanvas(isExpanded: self.$isDrawingExpanded)
                        .ignoresSafeArea()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            🖊DrawingCanvas(isExpanded: self.$isDrawingExpanded)
                                .frame(maxWidth: 650)
                            
                            Text("🎨 STICKER CAROUSEL TEST 🎨")
                                .font(.title)
                                .padding(40)
                                .background(Color.red)
                                .foregroundColor(.white)
                            
                            🎨StickerCarousel { sticker in
                                💥Feedback.light()
                            }
                            .frame(maxWidth: 650)
                        }
                        .padding(.top, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(self.$note.title)
            .onChange(of: self.note.title) { self.note.save(.title, $1) }
            .toolbar {
                if !self.isDrawingExpanded {
                    self.customizeButton()
                }
            }
            .animation(.default, value: self.isDrawingExpanded)
        }
    }
}

private extension 📝NoteTab {
    @ViewBuilder
    private func backgroundColor() -> some View {
        if self.colorScheme == .light {
            Color(uiColor: .secondarySystemBackground)
                .ignoresSafeArea()
        }
    }
    
    private func customizeButton() -> some View {
        Button {
            self.app.sheet = .customize(self.note.family)
            💥Feedback.selection()
        } label: {
            Label("Customize \"\(self.note.title)\"",
                  systemImage: "slider.horizontal.3")
        }
    }
}
