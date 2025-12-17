enum 🔖Tab: Hashable {
    case notesList
    case note(📝NoteFamily)
#if os(iOS)
    case option
#endif
    case info
}
