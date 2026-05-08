import AppKit
import Foundation

@main
@MainActor
final class MenuBarLyricsApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindowController: PreferencesWindowController!
    private let musicReader = MusicLyricsReader()
    private let accessibilityLyricsReader = MusicLyricsAccessibilityReader()
    private let pollingQueue = DispatchQueue(label: "MenuBarLyrics.polling")
    private var timer: Timer?
    private var accessibilityPermissionTimer: Timer?
    private var isRefreshInFlight = false
    private var isWaitingForAccessibilityPermission = false
    private var needsRefreshAfterCurrentRefresh = false
    private var latestDisplayLine: String?
    private var lyricsVisibilityItem: NSMenuItem!

    private var isLyricsVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: UserDefaultsKey.isLyricsVisible) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: UserDefaultsKey.isLyricsVisible)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.isLyricsVisible)
            preferencesWindowController?.isLyricsVisible = newValue
            updateLyricsVisibility()
        }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarLyricsApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferencesWindowController = PreferencesWindowController(isLyricsVisible: isLyricsVisible)
        preferencesWindowController.delegate = self
        setupStatusItem()
        updateLyricsVisibility()
        preferencesWindowController.show()
        accessibilityLyricsReader.requestPermissionIfNeeded()
        startAccessibilityPermissionMonitoringIfNeeded()
        startPolling()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "MenuBarLyrics")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        lyricsVisibilityItem = NSMenuItem(title: "显示菜单栏歌词", action: #selector(toggleLyricsVisibility), keyEquivalent: "")
        menu.addItem(lyricsVisibilityItem)
        menu.addItem(NSMenuItem(title: "打开设置...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MenuBarLyrics", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func startPolling() {
        scheduleLyricsRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleLyricsRefresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func scheduleLyricsRefresh() {
        guard !isRefreshInFlight else {
            return
        }

        isRefreshInFlight = true
        let musicReader = musicReader
        let accessibilityLyricsReader = accessibilityLyricsReader

        pollingQueue.async { [weak self, musicReader, accessibilityLyricsReader] in
            let resolvedDisplayLine = Self.resolveDisplayLine(
                musicReader: musicReader,
                accessibilityLyricsReader: accessibilityLyricsReader
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isRefreshInFlight = false
                self.applyDisplayLine(resolvedDisplayLine)

                if self.needsRefreshAfterCurrentRefresh {
                    self.needsRefreshAfterCurrentRefresh = false
                    self.scheduleLyricsRefresh()
                }
            }
        }
    }

    nonisolated private static func resolveDisplayLine(
        musicReader: MusicLyricsReader,
        accessibilityLyricsReader: MusicLyricsAccessibilityReader
    ) -> String {
        switch musicReader.readNowPlaying() {
        case .success(let nowPlaying):
            return displayLine(for: nowPlaying, accessibilityLyricsReader: accessibilityLyricsReader)
        case .failure(let error):
            return error.localizedDescription
        }
    }

    private func applyDisplayLine(_ resolvedDisplayLine: String) {
        guard resolvedDisplayLine != latestDisplayLine else {
            return
        }

        latestDisplayLine = resolvedDisplayLine
        updateMenuBarLyricsTitle()
    }

    private func startAccessibilityPermissionMonitoringIfNeeded() {
        guard !accessibilityLyricsReader.isPermissionGranted else {
            isWaitingForAccessibilityPermission = false
            accessibilityPermissionTimer?.invalidate()
            accessibilityPermissionTimer = nil
            return
        }

        isWaitingForAccessibilityPermission = true
        guard accessibilityPermissionTimer == nil else {
            return
        }

        accessibilityPermissionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAfterAccessibilityPermissionChangeIfNeeded()
            }
        }

        if let accessibilityPermissionTimer {
            RunLoop.main.add(accessibilityPermissionTimer, forMode: .common)
        }
    }

    private func refreshAfterAccessibilityPermissionChangeIfNeeded() {
        guard isWaitingForAccessibilityPermission,
              accessibilityLyricsReader.isPermissionGranted
        else {
            return
        }

        isWaitingForAccessibilityPermission = false
        accessibilityPermissionTimer?.invalidate()
        accessibilityPermissionTimer = nil
        latestDisplayLine = nil

        if isRefreshInFlight {
            needsRefreshAfterCurrentRefresh = true
            return
        }

        scheduleLyricsRefresh()
    }

    nonisolated private static func displayLine(
        for nowPlaying: NowPlaying,
        accessibilityLyricsReader: MusicLyricsAccessibilityReader
    ) -> String {
        guard nowPlaying.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nowPlaying.displayLine
        }

        switch accessibilityLyricsReader.readCurrentVisibleLyricLine(for: nowPlaying) {
        case .success(let line):
            return line
        case .failure(let error):
            return error.localizedDescription
        }
    }

    private func updateLyricsVisibility() {
        lyricsVisibilityItem?.state = isLyricsVisible ? .on : .off
        updateMenuBarLyricsTitle()
    }

    private func updateMenuBarLyricsTitle() {
        guard isLyricsVisible else {
            statusItem.button?.title = ""
            return
        }

        statusItem.button?.title = latestDisplayLine.map { " " + truncatedMenuBarTitle($0) } ?? ""
    }

    private func truncatedMenuBarTitle(_ title: String) -> String {
        let maxLength = 42

        guard title.count > maxLength else {
            return title
        }

        return String(title.prefix(maxLength - 1)) + "..."
    }

    @objc private func toggleLyricsVisibility() {
        isLyricsVisible.toggle()
    }

    @objc private func showPreferences() {
        preferencesWindowController.show()
    }

    @objc private func quit() {
        timer?.invalidate()
        accessibilityPermissionTimer?.invalidate()
        needsRefreshAfterCurrentRefresh = false
        NSApp.terminate(nil)
    }
}

extension MenuBarLyricsApp: PreferencesWindowControllerDelegate {
    func preferencesWindowController(
        _ controller: PreferencesWindowController,
        didChangeLyricsVisibility isVisible: Bool
    ) {
        isLyricsVisible = isVisible
    }
}

private enum UserDefaultsKey {
    static let isLyricsVisible = "isLyricsVisible"
}
