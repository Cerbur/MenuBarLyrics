import AppKit
import Foundation

@main
@MainActor
final class MenuBarLyricsApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: LyricsOverlayWindow!
    private let musicReader = MusicLyricsReader()
    private var timer: Timer?
    private var latestDisplayLine: String?

    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarLyricsApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayWindow = LyricsOverlayWindow()
        setupStatusItem()
        startPolling()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "MenuBarLyrics")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Lyrics", action: #selector(showLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Lyrics", action: #selector(hideLyrics), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MenuBarLyrics", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func startPolling() {
        refreshLyrics()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLyrics()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func refreshLyrics() {
        let displayLine: String

        switch musicReader.readNowPlaying() {
        case .success(let nowPlaying):
            displayLine = nowPlaying.displayLine
        case .failure(let error):
            displayLine = error.localizedDescription
        }

        guard displayLine != latestDisplayLine else {
            return
        }

        latestDisplayLine = displayLine
        overlayWindow.update(with: displayLine)
    }

    @objc private func showLyrics() {
        overlayWindow.show()
    }

    @objc private func hideLyrics() {
        overlayWindow.hide()
    }

    @objc private func quit() {
        timer?.invalidate()
        NSApp.terminate(nil)
    }
}
