import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let placeholderStack = UIStackView()
    private var stageTimer: Timer?
    private var currentStageIndex = 0
    private let stages = [
        "Reading reel",
        "Transcribing audio",
        "Finding key moments",
        "Building microreels",
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        self.configureView()
        self.importSharedReel()
    }

    deinit {
        self.stageTimer?.invalidate()
    }
}

private extension ShareViewController {
    func configureView() {
        self.view.backgroundColor = .systemBackground
        self.statusLabel.text = "Importing reel..."
        self.statusLabel.font = .preferredFont(forTextStyle: .headline)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.progressView.progress = 0.12
        self.progressView.translatesAutoresizingMaskIntoConstraints = false

        self.placeholderStack.axis = .vertical
        self.placeholderStack.alignment = .center
        self.placeholderStack.spacing = 8
        self.placeholderStack.translatesAutoresizingMaskIntoConstraints = false

        for index in 0..<5 {
            let bar = UIView()
            bar.backgroundColor = .secondaryLabel.withAlphaComponent(index == 0 ? 0.42 : 0.18)
            bar.layer.cornerRadius = 4
            bar.translatesAutoresizingMaskIntoConstraints = false
            self.placeholderStack.addArrangedSubview(bar)

            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: CGFloat(88 + (index * 20))),
                bar.heightAnchor.constraint(equalToConstant: 8),
            ])
        }

        let preview = UIView()
        preview.backgroundColor = .secondarySystemBackground
        preview.layer.cornerRadius = 14
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(self.placeholderStack)

        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 190),
            preview.heightAnchor.constraint(equalToConstant: 300),
            self.placeholderStack.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            self.placeholderStack.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
        ])

        let stack = UIStackView(arrangedSubviews: [preview, self.statusLabel, self.progressView])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor, constant: -24),
            self.statusLabel.widthAnchor.constraint(lessThanOrEqualTo: self.view.widthAnchor, constant: -48),
            self.progressView.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    func importSharedReel() {
        guard let extensionItems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            self.finishWithMessage("No shared content found.")
            return
        }

        Task {
            for item in extensionItems {
                for provider in item.attachments ?? [] {
                    if let url = await self.loadURL(from: provider),
                       Self.isSupportedReelURL(url) {
                        await self.importReel(url)
                        return
                    }

                    if let text = await self.loadText(from: provider),
                       let url = Self.extractSupportedURL(from: text) {
                        await self.importReel(url)
                        return
                    }
                }
            }

            await MainActor.run {
                self.finishWithMessage("Share an Instagram or TikTok reel URL.")
            }
        }
    }

    func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let text = String(data: data, encoding: .utf8),
                          let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else if let text = item as? String,
                          let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    func updateStatus(_ message: String) {
        self.statusLabel.text = message
    }

    func importReel(_ url: URL) async {
        await self.startImportAnimation()

        do {
            try await Self.importReelThroughBackend(url)
            await MainActor.run {
                self.stopImportAnimation()
                self.finishWithMessage("Reel imported. Open LockInNote to view it.")
            }
        } catch {
            await MainActor.run {
                self.stopImportAnimation()
                self.finishWithMessage(error.localizedDescription)
            }
        }
    }

    @MainActor
    func startImportAnimation() {
        self.currentStageIndex = 0
        self.updateStageUI()
        self.stageTimer?.invalidate()
        self.stageTimer = Timer.scheduledTimer(withTimeInterval: 2.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentStageIndex = min(self.currentStageIndex + 1, self.stages.count - 1)
            self.updateStageUI()
        }
    }

    @MainActor
    func stopImportAnimation() {
        self.stageTimer?.invalidate()
        self.stageTimer = nil
        self.progressView.setProgress(1, animated: true)
    }

    @MainActor
    func updateStageUI() {
        self.statusLabel.text = self.stages[self.currentStageIndex]
        let progress = Float(self.currentStageIndex + 1) / Float(self.stages.count + 1)
        self.progressView.setProgress(progress, animated: true)

        for (index, view) in self.placeholderStack.arrangedSubviews.enumerated() {
            UIView.animate(withDuration: 0.35) {
                view.backgroundColor = .secondaryLabel.withAlphaComponent(index == self.currentStageIndex % 5 ? 0.48 : 0.16)
                view.transform = index == self.currentStageIndex % 5 ? CGAffineTransform(scaleX: 1.08, y: 1) : .identity
            }
        }
    }

    @MainActor
    func finishWithMessage(_ message: String) {
        self.statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    static func extractSupportedURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        return matches
            .compactMap(\.url)
            .first(where: Self.isSupportedReelURL)
    }

    static func isSupportedReelURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return host.contains("instagram.com") || host.contains("tiktok.com")
    }

    static func importReelThroughBackend(_ reelURL: URL) async throws {
        guard let endpoint = URL(string: ReelBackendConfig.supabaseURL)?
            .appending(path: "functions/v1/reels") else {
            throw ImportError.missingConfig
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ReelBackendConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ReelBackendConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode([
            "url": reelURL.absoluteString,
            "profile_id": Self.defaultSocialProfileID.uuidString,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
                throw ImportError.backend(backendError.error)
            }

            throw ImportError.backend("Import failed.")
        }
    }

    static var defaultSocialProfileID: UUID {
        let defaults = UserDefaults.standard
        let key = "reelplay.socialProfileID"
        if let storedValue = defaults.string(forKey: key),
           let storedID = UUID(uuidString: storedValue) {
            return storedID
        }

        let profileID = UIDevice.current.identifierForVendor ?? UUID()
        defaults.set(profileID.uuidString, forKey: key)
        return profileID
    }
}

private struct BackendError: Decodable {
    let error: String
}

private enum ImportError: LocalizedError {
    case missingConfig
    case backend(String)

    var errorDescription: String? {
        switch self {
            case .missingConfig:
                "Missing backend config."
            case .backend(let message):
                message
        }
    }
}
