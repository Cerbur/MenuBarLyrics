import AppKit

@MainActor
// Reports preference changes back to the app delegate without coupling this window to storage.
// 将偏好设置变化回传给应用代理，避免设置窗口直接耦合持久化逻辑。
protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesWindowController(
        _ controller: PreferencesWindowController,
        didChangeLyricsVisibility isVisible: Bool
    )
}

@MainActor
// Small AppKit preferences window for the menu-bar lyric visibility setting.
// 用于控制菜单栏歌词显示状态的小型 AppKit 设置窗口。
final class PreferencesWindowController: NSWindowController {
    weak var delegate: PreferencesWindowControllerDelegate?

    private let visibilitySwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    // The app delegate owns persistence; this property mirrors the current setting in the UI.
    // 应用代理负责持久化；该属性只在 UI 中镜像当前设置。
    var isLyricsVisible = true {
        didSet {
            updateVisibilityControls()
        }
    }

    convenience init(isLyricsVisible: Bool) {
        // Build the window programmatically to keep this prototype lightweight and package-only.
        // 使用代码构建窗口，让原型保持轻量，并继续只依赖 Swift Package。
        let contentViewController = NSViewController()
        contentViewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))

        let window = NSWindow(
            contentRect: contentViewController.view.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MenuBarLyrics 设置"
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        self.isLyricsVisible = isLyricsVisible
        configureContent()
        updateVisibilityControls()
    }

    // Centering each time avoids reopening the panel partly off-screen after display changes.
    // 每次显示时重新居中，避免显示器变化后窗口重新打开在屏幕外。
    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // The content is intentionally compact because this app should remain menu-bar first.
    // 内容刻意保持紧凑，因为这个应用应以菜单栏体验为主。
    private func configureContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let titleLabel = NSTextField(labelWithString: "桌面歌词")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: "控制是否在顶部菜单栏显示当前播放歌词。")
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        let controlContainer = NSStackView()
        controlContainer.orientation = .horizontal
        controlContainer.alignment = .centerY
        controlContainer.spacing = 12
        controlContainer.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        controlContainer.wantsLayer = true
        controlContainer.layer?.cornerRadius = 8
        controlContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let controlTextStack = NSStackView()
        controlTextStack.orientation = .vertical
        controlTextStack.alignment = .leading
        controlTextStack.spacing = 4

        let controlTitleLabel = NSTextField(labelWithString: "显示菜单栏歌词")
        controlTitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        controlTitleLabel.textColor = .labelColor

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        controlTextStack.addArrangedSubview(controlTitleLabel)
        controlTextStack.addArrangedSubview(statusLabel)

        visibilitySwitch.setButtonType(.switch)
        visibilitySwitch.target = self
        visibilitySwitch.action = #selector(toggleLyricsVisibility)
        visibilitySwitch.controlSize = .large

        controlContainer.addArrangedSubview(controlTextStack)
        controlContainer.addArrangedSubview(visibilitySwitch)
        controlTextStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        visibilitySwitch.setContentHuggingPriority(.required, for: .horizontal)

        let quitButton = NSButton(title: "退出应用", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded

        let doneButton = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [quitButton, doneButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonStack.insertArrangedSubview(spacer, at: 1)

        let rootStack = NSStackView(views: [titleLabel, subtitleLabel, controlContainer, buttonStack])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10

        contentView.addSubview(rootStack)

        // Pin the stack to the content view and let AppKit controls keep their natural heights.
        // 将堆栈固定到内容视图边缘，并让 AppKit 控件保持自然高度。
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            controlContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            buttonStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    // Reflect the latest setting in both the switch state and the explanatory status text.
    // 同步开关状态和说明文字，反映最新设置。
    private func updateVisibilityControls() {
        visibilitySwitch.state = isLyricsVisible ? .on : .off
        statusLabel.stringValue = isLyricsVisible ? "已开启，歌词会显示在 macOS 顶部菜单栏。" : "已关闭，可随时从这里或菜单栏重新开启。"
    }

    // Forward user changes to the delegate so menu state, defaults, and title update together.
    // 将用户改动转发给代理，使菜单状态、默认值和标题一起更新。
    @objc private func toggleLyricsVisibility() {
        isLyricsVisible = visibilitySwitch.state == .on
        delegate?.preferencesWindowController(self, didChangeLyricsVisibility: isLyricsVisible)
    }

    @objc private func closeWindow() {
        close()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
