import UIKit
import UniformTypeIdentifiers

/// 书悦分享扩展：接收网页链接或书源 JSON 文本，
/// 逐条构造 `shuyue://import?url=…` / `shuyue://import?text=…` 深链回调主 App 导入。
///
/// 多个分享项（若干书源订阅链接 / 文本）会形成一条导入队列，主 App 侧逐条
/// 落入 `SYAppState.handleDeepLink` 归并展示汇总结果。
final class ShareViewController: UIViewController {
    private let activity = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let cancelButton = UIButton(type: .system)

    /// 书悦纸书卷主色（亮色 0x2E6A52，取自 SYPalette.accent；分享扩展不共享主 App 源码）。
    private let accentColorValue = UIColor(red: 46 / 255.0, green: 106 / 255.0, blue: 82 / 255.0, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildUI()
        statusLabel.text = "正在解析分享内容…"
        activity.startAnimating()
        collectAndForward()
    }

    // MARK: - 收集分享项

    private func collectAndForward() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else {
            showFailure("没有找到可导入的内容")
            return
        }

        var values: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    var text: String?
                    if let url = item as? URL {
                        text = url.absoluteString
                    } else if let nsurl = item as? NSURL {
                        text = nsurl.absoluteString
                    }
                    if let text {
                        lock.lock()
                        values.append(text)
                        lock.unlock()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    var text: String?
                    if let string = item as? String {
                        text = string
                    } else if let nsstring = item as? NSString {
                        text = nsstring as String
                    }
                    if let text {
                        lock.lock()
                        values.append(text)
                        lock.unlock()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let normalized = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !normalized.isEmpty else {
                self.showFailure("没有找到可导入的内容")
                return
            }
            self.statusLabel.text = "正在导入 \(normalized.count) 条书源…"
            self.forward(queue: normalized)
        }
    }

    // MARK: - 深链回调队列

    private func forward(queue: [String]) {
        var remaining = queue
        func next() {
            guard !remaining.isEmpty else {
                extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }
            let value = remaining.removeFirst()
            guard let url = deepLinkURL(for: value) else {
                next()
                return
            }
            extensionContext?.open(url) { _ in
                DispatchQueue.main.async { next() }
            }
        }
        next()
    }

    /// 构造 `shuyue://import?url=…` / `shuyue://import?text=…`。
    /// value 按 RFC 3986 安全集百分号编码，主 App 侧经 URLComponents 解码回原文。
    private func deepLinkURL(for value: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shuyue"
        components.host = "import"
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        components.percentEncodedQueryItems = [
            URLQueryItem(name: isWebURL(value) ? "url" : "text", value: encoded)
        ]
        return components.url
    }

    private func isWebURL(_ value: String) -> Bool {
        value.hasPrefix("http://") || value.hasPrefix("https://")
    }

    // MARK: - 界面

    private func buildUI() {
        let dim = UIView()
        dim.backgroundColor = UIColor(white: 0, alpha: 0.28)
        view.addSubview(dim)
        dim.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let card = UIView()
        card.backgroundColor = UIColor(white: 1, alpha: 1)
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 264),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 22, left: 20, bottom: 18, right: 20)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        let icon = UIImageView(image: UIImage(systemName: "square.stack.3d.up"))
        icon.tintColor = accentColorValue
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])
        stack.addArrangedSubview(icon)

        let title = UILabel()
        title.text = "导入书源"
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = UIColor(white: 0.12, alpha: 1)
        stack.addArrangedSubview(title)

        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = UIColor(white: 0.4, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.addArrangedSubview(activity)
        let activityLabel = UILabel()
        activityLabel.text = "请稍候…"
        activityLabel.font = UIFont.systemFont(ofSize: 13)
        activityLabel.textColor = UIColor(white: 0.4, alpha: 1)
        row.addArrangedSubview(activityLabel)
        stack.addArrangedSubview(row)

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.setTitleColor(accentColorValue, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        stack.addArrangedSubview(cancelButton)
    }

    private func showFailure(_ message: String) {
        activity.stopAnimating()
        statusLabel.text = message
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
