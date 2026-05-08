import AppKit

final class LyricsOverlayWindow: NSPanel {
    private let textField = NSTextField(labelWithString: "")

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let width: CGFloat = min(900, screenFrame.width - 80)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + 96,
            width: width,
            height: 96
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        configureTextField()
        show()
    }

    func update(with text: String) {
        textField.stringValue = text
    }

    func show() {
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func configureTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.alignment = .center
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 2
        textField.font = .systemFont(ofSize: 28, weight: .semibold)
        textField.textColor = .white
        textField.wantsLayer = true
        textField.layer?.shadowColor = NSColor.black.cgColor
        textField.layer?.shadowOpacity = 0.9
        textField.layer?.shadowRadius = 6
        textField.layer?.shadowOffset = CGSize(width: 0, height: -1)

        contentView = NSView()
        contentView?.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24),
            textField.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24),
            textField.centerYAnchor.constraint(equalTo: contentView!.centerYAnchor)
        ])
    }
}
