import AppKit
import Foundation

@main
@MainActor
// Owns the menu bar item, polling lifecycle, and user-facing app commands.
// 负责菜单栏项目、轮询生命周期以及用户可见的应用命令。
final class MenuBarLyricsApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindowController: PreferencesWindowController!
    private let musicReader = MusicLyricsReader()
    private let accessibilityLyricsReader = MusicLyricsAccessibilityReader()
    private let lyricsLineResolver = LyricsLineResolver()
    private let pollingQueue = DispatchQueue(label: "MenuBarLyrics.polling")
    private var timer: Timer?
    private var accessibilityPermissionTimer: Timer?
    private var isRefreshInFlight = false
    private var isWaitingForAccessibilityPermission = false
    private var needsRefreshAfterCurrentRefresh = false
    private var latestDisplayLine: String?
    private var lyricsVisibilityItem: NSMenuItem!

    // Separates "show this text" from states where a refresh should not disturb the current line.
    // 区分“显示这段文本”和“不应打断当前歌词”的刷新状态。
    private enum DisplayResolution: Sendable {
        case line(String)
        case accessibilityPermissionRequired(String)
        case keepCurrentLine
    }

    // Defaults to visible on first launch, then persists the user's explicit choice.
    // 首次启动默认显示歌词，之后持久化用户的明确选择。
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

    // Run as an accessory app so the experience stays in the menu bar instead of the Dock.
    // 以辅助应用模式运行，让体验停留在菜单栏而不是 Dock。
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
        showPreferencesOnFirstLaunchIfNeeded()
        accessibilityLyricsReader.requestPermissionIfNeeded()
        startAccessibilityPermissionMonitoringIfNeeded()
        startPolling()
    }

    // Builds the status item menu once; later state changes only update title and checkmark state.
    // 只构建一次状态栏菜单；后续状态变化只更新标题和勾选状态。
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

    // Poll once per second to keep lyric timing responsive without doing unnecessary work.
    // 每秒轮询一次，在保持歌词时间响应的同时避免过度工作。
    private func startPolling() {
        scheduleLyricsRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleLyricsRefresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // Prevent overlapping Music.app reads; a later timer tick will refresh again if needed.
    // 避免 Music.app 读取重叠；如有需要，后续定时器触发会再次刷新。
    private func scheduleLyricsRefresh() {
        guard !isRefreshInFlight else {
            return
        }

        isRefreshInFlight = true
        let musicReader = musicReader
        let accessibilityLyricsReader = accessibilityLyricsReader
        let lyricsLineResolver = lyricsLineResolver

        pollingQueue.async { [weak self, musicReader, accessibilityLyricsReader, lyricsLineResolver] in
            let displayResolution = Self.resolveDisplayLine(
                musicReader: musicReader,
                accessibilityLyricsReader: accessibilityLyricsReader,
                lyricsLineResolver: lyricsLineResolver
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isRefreshInFlight = false
                self.applyDisplayResolution(displayResolution)

                if self.needsRefreshAfterCurrentRefresh {
                    self.needsRefreshAfterCurrentRefresh = false
                    self.scheduleLyricsRefresh()
                }
            }
        }
    }

    // Runs off the main actor because AppleScript and Accessibility calls can block briefly.
    // 在主 actor 之外执行，因为 AppleScript 和辅助功能调用可能短暂阻塞。
    nonisolated private static func resolveDisplayLine(
        musicReader: MusicLyricsReader,
        accessibilityLyricsReader: MusicLyricsAccessibilityReader,
        lyricsLineResolver: LyricsLineResolver
    ) -> DisplayResolution {
        switch musicReader.readNowPlaying() {
        case .success(let nowPlaying):
            return displayLine(
                for: nowPlaying,
                accessibilityLyricsReader: accessibilityLyricsReader,
                lyricsLineResolver: lyricsLineResolver
            )
        case .failure(let error):
            return .line(error.localizedDescription)
        }
    }

    // Applies background refresh results on the main actor and avoids redundant title updates.
    // 在主 actor 上应用后台刷新结果，并避免重复更新菜单栏标题。
    private func applyDisplayResolution(_ displayResolution: DisplayResolution) {
        let resolvedDisplayLine: String

        switch displayResolution {
        case .line(let line):
            resolvedDisplayLine = line
        case .accessibilityPermissionRequired(let line):
            startAccessibilityPermissionMonitoringIfNeeded()
            resolvedDisplayLine = line
        case .keepCurrentLine:
            return
        }

        guard resolvedDisplayLine != latestDisplayLine else {
            return
        }

        latestDisplayLine = resolvedDisplayLine
        updateMenuBarLyricsTitle()
    }

    // Watch for the user granting Accessibility permission after macOS shows its system prompt.
    // 监听用户在 macOS 系统提示后授予辅助功能权限的变化。
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

    // When permission flips to granted, force a fresh read so visible Music.app lyrics appear quickly.
    // 当权限变为已授予时，强制重新读取，让 Music.app 可见歌词尽快显示。
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

    // Prefer local lyric metadata; use Accessibility only when Music.app exposes no local lyrics.
    // 优先使用本地歌词元数据；仅当 Music.app 没有本地歌词时才使用辅助功能读取。
    nonisolated private static func displayLine(
        for nowPlaying: NowPlaying,
        accessibilityLyricsReader: MusicLyricsAccessibilityReader,
        lyricsLineResolver: LyricsLineResolver
    ) -> DisplayResolution {
        guard nowPlaying.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .line(lyricsLineResolver.displayLine(for: nowPlaying))
        }

        switch accessibilityLyricsReader.readCurrentVisibleLyricLine(for: nowPlaying) {
        case .success(let line):
            return .line(line)
        case .failure(let error):
            switch error {
            case .permissionRequired:
                return .accessibilityPermissionRequired(error.localizedDescription)
            case .musicNotRunning:
                return .line(error.localizedDescription)
            case .lyricsPanelUnavailable:
                // Keep the previous line to avoid flicker while Music.app's lyrics panel settles.
                // 保留上一行，避免 Music.app 歌词面板刷新或暂不可见时菜单栏闪烁。
                return .keepCurrentLine
            }
        }
    }

    // Keep the menu checkmark and the status title in sync with the persisted visibility setting.
    // 让菜单勾选状态和状态栏标题与持久化的显示设置保持同步。
    private func updateLyricsVisibility() {
        lyricsVisibilityItem?.state = isLyricsVisible ? .on : .off
        updateMenuBarLyricsTitle()
    }

    // Show preferences on first launch so users discover the visibility control and permissions context.
    // 首次启动展示设置窗口，帮助用户发现显示开关和权限相关入口。
    private func showPreferencesOnFirstLaunchIfNeeded() {
        guard UserDefaults.standard.object(forKey: UserDefaultsKey.hasShownPreferencesOnLaunch) == nil else {
            return
        }

        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasShownPreferencesOnLaunch)
        preferencesWindowController.show()
    }

    // Empty title keeps the status item collapsed while still preserving its menu and icon.
    // 标题为空时状态项保持收起，但仍保留菜单和图标入口。
    private func updateMenuBarLyricsTitle() {
        guard isLyricsVisible else {
            statusItem.button?.title = ""
            return
        }

        statusItem.button?.title = latestDisplayLine.map { " " + truncatedMenuBarTitle($0) } ?? ""
    }

    // Keep lyrics short enough for crowded menu bars.
    // 将歌词限制在适合拥挤菜单栏的长度。
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
    static let hasShownPreferencesOnLaunch = "hasShownPreferencesOnLaunch"
}
