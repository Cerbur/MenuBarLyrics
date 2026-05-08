import AppKit

@MainActor
protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesWindowController(
        _ controller: PreferencesWindowController,
        didChangeLyricsVisibility isVisible: Bool
    )
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    weak var delegate: PreferencesWindowControllerDelegate?

    private let visibilitySwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    var isLyricsVisible = true {
        didSet {
            updateVisibilityControls()
        }
    }

    convenience init(isLyricsVisible: Bool) {
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

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            controlContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            buttonStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func updateVisibilityControls() {
        visibilitySwitch.state = isLyricsVisible ? .on : .off
        statusLabel.stringValue = isLyricsVisible ? "已开启，歌词会显示在 macOS 顶部菜单栏。" : "已关闭，可随时从这里或菜单栏重新开启。"
    }

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
