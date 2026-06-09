import UIKit

/// OpenLess 键盘 = Flow 式语音面板（不做打字键盘）。
///
/// 约束：键盘扩展无法录音。麦克风键 → 跳主 App（openless://dictate）录音+识别，
/// 结果写入 App Group；返回本输入框时本类从共享容器取出并用 textDocumentProxy 插入。
///
/// 注意：跳转(openURL)与读 App Group 都**需要「允许完全访问」**；未开时给出提示。
final class KeyboardViewController: UIInputViewController {

    private let appGroup = "group.top.openless.ios"
    private let pendingKey = "pendingInsertText"   // 与 Shared/Handoff.swift 保持一致
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPanel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateHint()
        insertPendingIfAny()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        insertPendingIfAny()
    }

    /// 取出主 App 识别好的文本并插入。
    private func insertPendingIfAny() {
        guard let d = UserDefaults(suiteName: appGroup),
              let text = d.string(forKey: pendingKey), !text.isEmpty else { return }
        d.removeObject(forKey: pendingKey)
        textDocumentProxy.insertText(text)
    }

    /// 根据是否拥有完全访问更新提示（未开则跳转/回插都用不了）。
    private func updateHint() {
        if hasFullAccess {
            hintLabel.text = "轻点一下，跳转说话"
            hintLabel.textColor = .secondaryLabel
        } else {
            hintLabel.text = "请到 设置→通用→键盘→OpenLess 开启「允许完全访问」"
            hintLabel.textColor = .systemRed
        }
    }

    // MARK: - 布局

    private func buildPanel() {
        let h = view.heightAnchor.constraint(equalToConstant: 196)
        h.priority = UILayoutPriority(999)
        h.isActive = true

        let toolbar = makeToolbar()

        let mic = makeMicButton()
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.text = "轻点一下，跳转说话"

        let center = UIStackView(arrangedSubviews: [mic, hintLabel])
        center.axis = .vertical
        center.spacing = 12
        center.alignment = .center

        let root = UIStackView(arrangedSubviews: [toolbar, center])
        root.axis = .vertical
        root.spacing = 18
        root.alignment = .fill
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            center.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 8),
        ])
    }

    // MARK: - 顶部工具条：品牌 + 切键盘 / 删除 / 设置

    private func makeToolbar() -> UIView {
        let brand = UILabel()
        brand.text = "OpenLess"
        brand.font = .systemFont(ofSize: 13, weight: .semibold)
        brand.textColor = .secondaryLabel

        let spacerView = UIView()
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var items: [UIView] = [brand, spacerView]
        if needsInputModeSwitchKey {
            let globe = iconButton("globe")
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            items.append(globe)
        }
        let del = iconButton("delete.left")
        del.addTarget(self, action: #selector(onDelete), for: .touchUpInside)
        items.append(del)

        let gear = iconButton("gearshape")
        gear.addTarget(self, action: #selector(onSettings), for: .touchUpInside)
        items.append(gear)

        let bar = UIStackView(arrangedSubviews: items)
        bar.axis = .horizontal
        bar.spacing = 18
        bar.alignment = .center
        bar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return bar
    }

    /// 无背景的纯图标按钮（不再额外套白底方块），加大点击热区。
    private func iconButton(_ systemName: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        b.tintColor = .label
        b.widthAnchor.constraint(equalToConstant: 40).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    // MARK: - 大麦克风按钮

    private func makeMicButton() -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.baseBackgroundColor = .label
        cfg.baseForegroundColor = .systemBackground
        cfg.title = "语音输入"
        cfg.image = UIImage(systemName: "mic.fill")
        cfg.imagePadding = 8
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        let b = UIButton(configuration: cfg)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.addTarget(self, action: #selector(onMic), for: .touchUpInside)
        return b
    }

    // MARK: - 动作

    @objc private func onMic() {
        guard hasFullAccess else { updateHint(); return }
        openHostApp("openless://dictate")
    }

    @objc private func onSettings() {
        guard hasFullAccess else { updateHint(); return }
        openHostApp("openless://settings")
    }

    @objc private func onDelete() { textDocumentProxy.deleteBackward() }

    /// 键盘扩展打开容器 App：沿响应链找到 UIApplication 调现代 open；老选择器作兜底。
    /// 需要「允许完全访问」。
    private func openHostApp(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        // 首选：找到 UIApplication 实例调 open(_:options:completionHandler:)
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
        // 兜底：老的 openURL: 选择器（部分系统版本仍可用）
        let selector = NSSelectorFromString("openURL:")
        responder = self
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
