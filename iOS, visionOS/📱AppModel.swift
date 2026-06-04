import SwiftUI

class 📱AppModel: ObservableObject {
    @Published var tab: 🔖Tab = .notesList
    @Published var sheet: 💬Sheet? = nil
    @Published var sharedReelURL: URL? = nil
    @Published private(set) var preferTextFieldFocus: 📝NoteFamily? = nil
    let primaryNote: 📝NoteModel = .init(.primary)
    let secondaryNote: 📝NoteModel = .init(.secondary)
    let tertiaryNote: 📝NoteModel = .init(.tertiary)
    let inAppPurchaseModel: 🛒InAppPurchaseModel = .init(id: "LockInNote.adfree")
}

extension 📱AppModel {
    func handle(_ ⓦidgetURL: URL) {
        if let sharedURL = Self.decodeSharedReelURL(ⓦidgetURL) {
            self.sharedReelURL = sharedURL
            self.tab = .reels
            💥Feedback.light()
            return
        }

        if Self.isSupportedReelURL(ⓦidgetURL) {
            self.sharedReelURL = ⓦidgetURL
            self.tab = .reels
            💥Feedback.light()
            return
        }

        guard let ⓣarget = 📝NoteFamily.decode(ⓦidgetURL) else {
            assertionFailure("Failed url decode")
            return
        }
        switch self.sheet {
            case .ad: 
                return
            case .onboarding:
                self.sheet = nil
                self.tab = .note(ⓣarget)
            case .customize(let ⓒustomizingNote):
                guard ⓣarget != ⓒustomizingNote else { return }
                self.sheet = nil
                self.tab = .note(ⓣarget)
            case .none:
                self.tab = .note(ⓣarget)
        }
        if !UserDefaults.standard.bool(forKey: "preventAutomaticKeyboard") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.25))
                self.preferTextFieldFocus = ⓣarget
            }
        }
        💥Feedback.light()
    }

    static func isSupportedReelURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return host.contains("instagram.com") || host.contains("tiktok.com")
    }

    static func decodeSharedReelURL(_ url: URL) -> URL? {
        guard url.scheme == "luvly",
              url.host(percentEncoded: false) == "import-reel",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let sharedURL = URL(string: value),
              Self.isSupportedReelURL(sharedURL) else {
            return nil
        }

        return sharedURL
    }

    func handle(_ ⓕocus: inout Bool) {
        ⓕocus = true
        self.preferTextFieldFocus = nil
    }
}
