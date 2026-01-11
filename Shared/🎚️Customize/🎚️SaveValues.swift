import SwiftUI

struct 🎚️SaveValues: ViewModifier {
    @EnvironmentObject var note: 📝NoteModel
    private var ⓒases: [📝NoteProperty] = .Element.allCases
    func body(content: Content) -> some View {
        if let ⓒase = ⓒases.last {
            content
                .modifier(Self.SaveValue(property: ⓒase))
                .modifier(Self(ⓒases: self.ⓒases.dropLast()))
        } else {
            content
        }
    }
    private struct SaveValue: ViewModifier {
        @EnvironmentObject var note: 📝NoteModel
        var property: 📝NoteProperty
        func body(content: Content) -> some View {
            switch self.property {
                case .text, .title, .drawingData, .stickerData: content
                case .fontWeight: content.onChange(of: self.note.fontWeight) { self.save($1) }
                case .fontDesign: content.onChange(of:self.note.fontDesign) { self.save($1) }
                case .italic: content.onChange(of:self.note.italic) { self.save($1) }
                case .multilineTextAlignment: content.onChange(of:self.note.multilineTextAlignment) { self.save($1) }
                case .empty_type: content.onChange(of:self.note.empty_type) { self.save($1) }
                case .empty_iconSize: content.onChange(of:self.note.empty_iconSize) { self.save($1) }
                case .empty_userText: content.onChange(of:self.note.empty_userText) { self.save($1) }
                case .system_appearanceMode: content.onChange(of:self.note.system_appearanceMode) { self.save($1) }
                case .system_fontSize: content.onChange(of:self.note.system_fontSize) { self.save($1) }
                case .system_hierarchical: content.onChange(of:self.note.system_hierarchical) { self.save($1) }
                case .system_padding: content.onChange(of:self.note.system_padding) { self.save($1) }
                case .system_contentAlignment: content.onChange(of:self.note.system_contentAlignment) { self.save($1) }
                case .system_textColor: content.onChange(of:self.note.system_textColor) { self.save(🎚️Color($1)) }
                case .system_backgroundColor: content.onChange(of:self.note.system_backgroundColor) { self.save(🎚️Color($1)) }
                case .system_backgroundGradient: content.onChange(of:self.note.system_backgroundGradient) { self.save($1) }
                case .system_doubleSizeOnLargeWidget: content.onChange(of:self.note.system_doubleSizeOnLargeWidget) { self.save($1) }
                case .accessory_fontSize: content.onChange(of:self.note.accessory_fontSize) { self.save($1) }
                case .accessory_hierarchical: content.onChange(of:self.note.accessory_hierarchical) { self.save($1) }
                case .accessoryCircular_backgroundForIOS16AndWatchOS: content.onChange(of:self.note.accessoryCircular_backgroundForIOS16AndWatchOS) { self.save($1) }
            }
        }
        private func save(_ ⓥalue: some Codable) {
            self.note.save(self.property, ⓥalue)
        }
    }
}
