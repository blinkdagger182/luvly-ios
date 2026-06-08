import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let placeholderStack = UIStackView()
    private let statusLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let openButton = UIButton()
    private let countdownLabel = UILabel()
    private let activityView = UIActivityIndicatorView(style: .medium)

    private var autoOpenTimer: Timer?
    private var barAnimationTimer: Timer?
    private var countdownRemaining = 2
    private var pendingLuvlyURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.configureView()
        self.showFindingState()
        Task { await self.extractAndPrepare() }
    }

    deinit {
        self.autoOpenTimer?.invalidate()
        self.barAnimationTimer?.invalidate()
    }
}

// MARK: - Phases

private extension ShareViewController {
    @MainActor
    func showFindingState() {
        self.activityView.startAnimating()
        self.activityView.isHidden = false
        self.statusLabel.text = "Finding reel..."
        self.subtitleLabel.isHidden = true
        self.openButton.isHidden = true
        self.countdownLabel.isHidden = true
    }

    @MainActor
    func showReadyState(luvlyURL: URL) {
        self.pendingLuvlyURL = luvlyURL

        self.activityView.stopAnimating()
        self.activityView.isHidden = true

        UIView.animate(withDuration: 0.2) {
            self.statusLabel.text = "Open in Luvly"
            self.subtitleLabel.text = "Loading with full progress view inside the app."
            self.subtitleLabel.isHidden = false
            self.openButton.isHidden = false
        }

        self.animatePlaceholderBars()
        self.startCountdown()
    }

    @MainActor
    func showErrorState(_ message: String) {
        self.activityView.stopAnimating()
        self.activityView.isHidden = true
        self.statusLabel.text = message
        self.subtitleLabel.text = "Close and try again."
        self.subtitleLabel.isHidden = false
        self.openButton.isHidden = true
        self.countdownLabel.isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    func startCountdown() {
        self.countdownRemaining = 2
        self.updateCountdownLabel()
        self.countdownLabel.isHidden = false

        self.autoOpenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                timer.invalidate()
                self.openInApp()
            } else {
                self.updateCountdownLabel()
            }
        }
    }

    @MainActor
    func updateCountdownLabel() {
        self.countdownLabel.text = "Opening automatically in \(self.countdownRemaining)s"
    }

    func animatePlaceholderBars() {
        var barIndex = 0
        self.barAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self else { return }
            for (index, view) in self.placeholderStack.arrangedSubviews.enumerated() {
                UIView.animate(withDuration: 0.3) {
                    view.backgroundColor = .secondaryLabel.withAlphaComponent(index == barIndex % 5 ? 0.52 : 0.16)
                    view.transform = index == barIndex % 5 ? CGAffineTransform(scaleX: 1.1, y: 1) : .identity
                }
            }
            barIndex += 1
        }
    }
}

// MARK: - URL Extraction

private extension ShareViewController {
    func extractAndPrepare() async {
        guard let extensionItems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            await self.showErrorState("No shared content found.")
            return
        }

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if let url = await self.loadURL(from: provider),
                   Self.isSupportedReelURL(url),
                   let luvlyURL = Self.luvlyImportURL(for: url) {
                    await self.showReadyState(luvlyURL: luvlyURL)
                    return
                }

                if let text = await self.loadText(from: provider),
                   let url = Self.extractSupportedURL(from: text),
                   let luvlyURL = Self.luvlyImportURL(for: url) {
                    await self.showReadyState(luvlyURL: luvlyURL)
                    return
                }
            }
        }

        await self.showErrorState("Share an Instagram or TikTok reel link.")
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
                } else if let text = item as? String, let url = URL(string: text) {
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

    static func extractSupportedURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.compactMap(\.url).first(where: Self.isSupportedReelURL)
    }

    static func isSupportedReelURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host.contains("instagram.com") || host.contains("tiktok.com")
    }

    static func luvlyImportURL(for reelURL: URL) -> URL? {
        guard var components = URLComponents(string: "luvly://import-reel") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: reelURL.absoluteString)]
        return components.url
    }
}

// MARK: - Open in App

private extension ShareViewController {
    @objc func openButtonTapped() {
        self.autoOpenTimer?.invalidate()
        self.autoOpenTimer = nil
        self.openInApp()
    }

    func openInApp() {
        guard let url = self.pendingLuvlyURL else {
            self.extensionContext?.completeRequest(returningItems: nil)
            return
        }
        self.extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - View Setup

private extension ShareViewController {
    func configureView() {
        self.view.backgroundColor = .systemBackground

        // Placeholder card
        for index in 0..<5 {
            let bar = UIView()
            bar.backgroundColor = .secondaryLabel.withAlphaComponent(index == 0 ? 0.42 : 0.18)
            bar.layer.cornerRadius = 4
            bar.translatesAutoresizingMaskIntoConstraints = false
            self.placeholderStack.addArrangedSubview(bar)
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: CGFloat(88 + (index * 18))),
                bar.heightAnchor.constraint(equalToConstant: 8),
            ])
        }

        self.placeholderStack.axis = .vertical
        self.placeholderStack.alignment = .center
        self.placeholderStack.spacing = 10
        self.placeholderStack.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(self.placeholderStack)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 180),
            card.heightAnchor.constraint(equalToConstant: 280),
            self.placeholderStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            self.placeholderStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])

        // Activity indicator
        self.activityView.color = .label
        self.activityView.translatesAutoresizingMaskIntoConstraints = false

        // Labels
        self.statusLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.subtitleLabel.textColor = .secondaryLabel
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Open button
        var config = UIButton.Configuration.filled()
        config.title = "Open in Reelplay"
        config.image = UIImage(systemName: "arrow.up.right.circle.fill")
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.baseBackgroundColor = .label
        config.baseForegroundColor = .systemBackground
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 24, bottom: 15, trailing: 24)
        self.openButton.configuration = config
        self.openButton.addTarget(self, action: #selector(self.openButtonTapped), for: .touchUpInside)
        self.openButton.translatesAutoresizingMaskIntoConstraints = false

        // Countdown
        self.countdownLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        self.countdownLabel.textColor = .tertiaryLabel
        self.countdownLabel.textAlignment = .center
        self.countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        // Stack it all
        let textStack = UIStackView(arrangedSubviews: [
            self.activityView,
            self.statusLabel,
            self.subtitleLabel,
        ])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 6
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = UIStackView(arrangedSubviews: [
            self.openButton,
            self.countdownLabel,
        ])
        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let root = UIStackView(arrangedSubviews: [card, textStack, actionStack])
        root.axis = .vertical
        root.alignment = .center
        root.spacing = 20
        root.setCustomSpacing(24, after: textStack)
        root.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(root)

        NSLayoutConstraint.activate([
            root.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            root.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor, constant: -28),
            self.subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
    }
}
