import ApplicationServices
import AppKit
import Foundation

// User-facing failures from scraping the visible Music.app lyrics panel.
// 从 Music.app 可见歌词面板读取时产生的用户可读错误。
enum MusicLyricsAccessibilityError: LocalizedError, Sendable {
    case permissionRequired
    case musicNotRunning
    case lyricsPanelUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "请为 MenuBarLyrics 开启辅助功能权限。"
        case .musicNotRunning:
            return "Music.app 未运行。"
        case .lyricsPanelUnavailable:
            return "请打开 Music.app 的歌词面板。"
        }
    }
}

// Reads Apple Music's visible lyrics UI through macOS Accessibility when local lyrics are empty.
// 当本地歌词为空时，通过 macOS 辅助功能读取 Apple Music 当前可见的歌词 UI。
final class MusicLyricsAccessibilityReader: @unchecked Sendable {
    // A possible lyric text node plus the UI context needed to rank it.
    // 一个可能的歌词文本节点，以及用于排序判断的 UI 上下文。
    private struct TextCandidate {
        let text: String
        let frame: CGRect?
        let isSelected: Bool
        let isFocused: Bool
        let isInLyricsPanel: Bool
        let lyricsPanelFrame: CGRect?
    }

    private let maximumTraversalDepth = 12
    private let maximumTraversalNodes = 1_500
    private let accessibilityMessagingTimeout: Float = 0.2

    // AX trust can change while the app is running after the user responds to the system prompt.
    // 用户响应系统提示后，辅助功能信任状态可能在应用运行中发生变化。
    var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    // Ask macOS to show the Accessibility permission prompt when permission is missing.
    // 在缺少权限时请求 macOS 显示辅助功能权限提示。
    func requestPermissionIfNeeded() {
        guard !isPermissionGranted else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Traverse Music.app windows and pick the best currently visible lyric text.
    // 遍历 Music.app 窗口，并选择当前最可能可见的一行歌词文本。
    func readCurrentVisibleLyricLine(for nowPlaying: NowPlaying) -> Result<String, MusicLyricsAccessibilityError> {
        guard AXIsProcessTrusted() else {
            return .failure(.permissionRequired)
        }

        guard let musicApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            return .failure(.musicNotRunning)
        }

        let appElement = AXUIElementCreateApplication(musicApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, accessibilityMessagingTimeout)
        let roots = windows(in: appElement)
        var candidates: [TextCandidate] = []
        var visitedElements = Set<CFHashCode>()
        var remainingNodeBudget = maximumTraversalNodes

        // Music.app's Accessibility tree can be large, so traversal is both depth- and node-limited.
        // Music.app 的辅助功能树可能很大，因此同时限制遍历深度和节点数量。
        for root in roots {
            candidates.append(
                contentsOf: collectTextCandidates(
                    from: root,
                    depth: 0,
                    inheritedSelection: false,
                    inheritedFocus: false,
                    lyricsPanelFrame: nil,
                    visitedElements: &visitedElements,
                    remainingNodeBudget: &remainingNodeBudget
                )
            )
        }

        guard let selectedLine = selectBestCandidate(from: candidates, for: nowPlaying) else {
            return .failure(.lyricsPanelUnavailable)
        }

        return .success(selectedLine)
    }

    // Fall back to the app element because some AX states do not expose windows immediately.
    // 回退到应用元素本身，因为某些辅助功能状态下窗口不会立即暴露。
    private func windows(in appElement: AXUIElement) -> [AXUIElement] {
        if let windows = elementArrayAttribute(kAXWindowsAttribute, from: appElement), !windows.isEmpty {
            return windows
        }

        return [appElement]
    }

    // Recursively gather text nodes while carrying selected/focused/panel context down the tree.
    // 递归收集文本节点，并沿树向下传递选中、焦点和歌词面板上下文。
    private func collectTextCandidates(
        from element: AXUIElement,
        depth: Int,
        inheritedSelection: Bool,
        inheritedFocus: Bool,
        lyricsPanelFrame inheritedLyricsPanelFrame: CGRect?,
        visitedElements: inout Set<CFHashCode>,
        remainingNodeBudget: inout Int
    ) -> [TextCandidate] {
        guard depth < maximumTraversalDepth, remainingNodeBudget > 0 else {
            return []
        }

        let elementID = CFHash(element)
        guard visitedElements.insert(elementID).inserted else {
            return []
        }

        remainingNodeBudget -= 1
        AXUIElementSetMessagingTimeout(element, accessibilityMessagingTimeout)

        var candidates: [TextCandidate] = []
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let isSelected = inheritedSelection || (boolAttribute(kAXSelectedAttribute, from: element) ?? false)
        let isFocused = inheritedFocus || (boolAttribute(kAXFocusedAttribute, from: element) ?? false)
        let elementFrame = frame(of: element)
        let lyricsPanelFrame = self.lyricsPanelFrame(
            for: element,
            role: role,
            frame: elementFrame,
            inheritedLyricsPanelFrame: inheritedLyricsPanelFrame
        )
        let text = bestTextValue(from: element, role: role)

        // Only collect text after a lyrics panel has been identified, reducing sidebar noise.
        // 仅在识别到歌词面板后收集文本，减少侧边栏等界面文本干扰。
        if let text,
           lyricsPanelFrame != nil,
           isPotentialLyricText(text) {
            candidates.append(
                TextCandidate(
                    text: text,
                    frame: elementFrame,
                    isSelected: isSelected,
                    isFocused: isFocused,
                    isInLyricsPanel: lyricsPanelFrame != nil,
                    lyricsPanelFrame: lyricsPanelFrame
                )
            )
        }

        let children = uniqueElements(
            (elementArrayAttribute(kAXVisibleChildrenAttribute, from: element) ?? [])
                + (elementArrayAttribute(kAXChildrenAttribute, from: element) ?? [])
        )

        for child in children {
            candidates.append(
                contentsOf: collectTextCandidates(
                    from: child,
                    depth: depth + 1,
                    inheritedSelection: isSelected,
                    inheritedFocus: isFocused,
                    lyricsPanelFrame: lyricsPanelFrame,
                    visitedElements: &visitedElements,
                    remainingNodeBudget: &remainingNodeBudget
                )
            )
        }

        return candidates
    }

    // AX controls expose readable text through different attributes depending on role and OS version.
    // 不同角色和系统版本的 AX 控件会通过不同属性暴露可读文本。
    private func bestTextValue(from element: AXUIElement, role: String) -> String? {
        let textRoles = [
            kAXStaticTextRole,
            kAXTextAreaRole,
            kAXButtonRole
        ].map { $0 as String }

        guard textRoles.contains(role) else {
            return nil
        }

        return stringAttribute(kAXValueAttribute, from: element)
            ?? stringAttribute(kAXTitleAttribute, from: element)
            ?? stringAttribute(kAXDescriptionAttribute, from: element)
    }

    // Filter out controls and metadata, then rank visible lyric candidates by UI state and position.
    // 过滤控件和歌曲元数据，再根据 UI 状态与位置对可见歌词候选排序。
    private func selectBestCandidate(from candidates: [TextCandidate], for nowPlaying: NowPlaying) -> String? {
        let lyricPanelCandidates = candidates
            .filter { !isTrackMetadata($0.text, nowPlaying: nowPlaying) }
            .filter(\.isInLyricsPanel)
            .filter(isVisibleLyricPanelCandidate)

        guard !lyricPanelCandidates.isEmpty else {
            return nil
        }

        let bestCandidate = uniqueByBestCandidateText(lyricPanelCandidates)
            .min(by: isBetterCandidate)
        return bestCandidate?.text
    }

    // Detect the lyrics panel by looking for a large group labelled "Lyrics" or "歌词".
    // 通过带有 “Lyrics” 或 “歌词” 标签的大尺寸分组识别歌词面板。
    private func lyricsPanelFrame(
        for element: AXUIElement,
        role: String,
        frame: CGRect?,
        inheritedLyricsPanelFrame: CGRect?
    ) -> CGRect? {
        if let inheritedLyricsPanelFrame {
            return inheritedLyricsPanelFrame
        }

        guard role == (kAXGroupRole as String),
              let frame,
              frame.width >= 160,
              frame.height >= 300
        else {
            return nil
        }

        let labels = [
            stringAttribute(kAXValueAttribute, from: element),
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXDescriptionAttribute, from: element)
        ].compactMap { $0 }

        return labels.contains(where: isLyricsPanelLabel) ? frame : nil
    }

    // Keep candidates inside the central lyrics area, excluding the header and bottom controls.
    // 只保留歌词面板中部区域的候选项，排除顶部标题和底部控制区。
    private func isVisibleLyricPanelCandidate(_ candidate: TextCandidate) -> Bool {
        guard let frame = candidate.frame,
              let panelFrame = candidate.lyricsPanelFrame
        else {
            return false
        }

        guard frame.width >= panelFrame.width * 0.45,
              frame.height >= 12,
              frame.minX >= panelFrame.minX,
              frame.maxX <= panelFrame.maxX + 1
        else {
            return false
        }

        let topInset: CGFloat = 44
        let bottomInset: CGFloat = 80
        return frame.minY >= panelFrame.minY + topInset
            && frame.maxY <= panelFrame.maxY - bottomInset
    }

    // Prefer upper visible lines, then longer text when two candidates share the same vertical start.
    // 优先选择更靠上的可见行；垂直位置相同时选择文本更长的候选。
    private func lyricPanelSort(_ lhs: TextCandidate, _ rhs: TextCandidate) -> Bool {
        let lhsMinY = lhs.frame?.minY ?? .greatestFiniteMagnitude
        let rhsMinY = rhs.frame?.minY ?? .greatestFiniteMagnitude
        if lhsMinY != rhsMinY {
            return lhsMinY < rhsMinY
        }

        return lhs.text.count > rhs.text.count
    }

    // Higher scores are better; tie-breakers use stable visual ordering.
    // 分数越高越优；分数相同时使用稳定的视觉顺序作为决胜条件。
    private func isBetterCandidate(_ lhs: TextCandidate, _ rhs: TextCandidate) -> Bool {
        let lhsScore = candidateScore(lhs)
        let rhsScore = candidateScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        return lyricPanelSort(lhs, rhs)
    }

    // Selected and focused AX states are strong hints for the current live lyric line.
    // AX 的选中和焦点状态通常强烈暗示当前正在播放的歌词行。
    private func candidateScore(_ candidate: TextCandidate) -> Int {
        var score = 0

        if candidate.isSelected {
            score += 100
        }

        if candidate.isFocused {
            score += 80
        }

        if candidate.frame != nil {
            score += 10
        }

        return score
    }

    // Deduplicate repeated AX nodes while keeping the strongest candidate for each text value.
    // 去重重复的 AX 文本节点，同时为每段文本保留最强候选。
    private func uniqueByBestCandidateText(_ candidates: [TextCandidate]) -> [TextCandidate] {
        var bestCandidatesByText: [String: TextCandidate] = [:]

        for candidate in candidates {
            let key = normalized(candidate.text)
            guard let existing = bestCandidatesByText[key] else {
                bestCandidatesByText[key] = candidate
                continue
            }

            if isBetterCandidate(candidate, existing) {
                bestCandidatesByText[key] = candidate
            }
        }

        return Array(bestCandidatesByText.values)
    }

    // Accessibility trees can expose the same element through visible and full child arrays.
    // 辅助功能树可能通过可见子节点和完整子节点数组暴露同一个元素。
    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen = Set<CFHashCode>()
        var result: [AXUIElement] = []

        for element in elements {
            guard seen.insert(CFHash(element)).inserted else {
                continue
            }

            result.append(element)
        }

        return result
    }

    // Reject obvious UI chrome while allowing short real lyric fragments.
    // 排除明显的界面文本，同时允许较短的真实歌词片段。
    private func isPotentialLyricText(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 2, trimmedText.count <= 180 else {
            return false
        }

        guard !isTimeLikeText(trimmedText),
              !isOnlyPunctuation(trimmedText)
        else {
            return false
        }

        let ignoredValues = [
            "Music",
            "Lyrics",
            "歌词",
            "翻译",
            "Search",
            "搜索",
            "Playing Next",
            "待播清单",
            "Listen Now",
            "现在就听",
            "Browse",
            "浏览",
            "Radio",
            "广播",
            "Library",
            "资料库",
            "Recently Added",
            "最近添加",
            "Artists",
            "艺人",
            "Albums",
            "专辑",
            "Songs",
            "歌曲",
            "歌曲排行",
            "Made for You",
            "为你打造"
        ].map(normalized)

        return !ignoredValues.contains(normalized(trimmedText))
    }

    // Ignore duration and timestamp labels such as "3:45" or "01:02:03".
    // 忽略类似 “3:45” 或 “01:02:03” 的时长和时间标签。
    private func isTimeLikeText(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else {
            return false
        }

        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    // Standalone punctuation or symbols are usually separators, not lyric text.
    // 单独的标点或符号通常是分隔元素，不是歌词文本。
    private func isOnlyPunctuation(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    // The lyrics panel may repeat title, artist, or album; those should not be shown as lyrics.
    // 歌词面板可能重复展示标题、艺人或专辑，这些不应作为歌词显示。
    private func isTrackMetadata(_ text: String, nowPlaying: NowPlaying) -> Bool {
        let normalizedText = normalized(text)
        let metadata = [
            nowPlaying.title,
            nowPlaying.artist,
            nowPlaying.album
        ].map(normalized)

        return metadata.contains(normalizedText)
    }

    // Music.app localizes the lyrics panel label; currently support English and Chinese UI.
    // Music.app 会本地化歌词面板标签；当前支持英文和中文界面。
    private func isLyricsPanelLabel(_ text: String) -> Bool {
        ["歌词", "Lyrics"].map(normalized).contains(normalized(text))
    }

    // Normalize text before comparison so localized UI casing and accents do not affect matching.
    // 比较前先规范化文本，避免界面大小写和重音差异影响匹配。
    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // Small typed wrappers keep raw AX attribute calls localized and easier to audit.
    // 小型类型化包装让原始 AX 属性读取集中在一处，便于审查。
    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Reads a Boolean AX attribute when present.
    // 在属性存在时读取布尔类型的 AX 属性。
    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    // Reads an array of child AX elements when present.
    // 在属性存在时读取 AX 子元素数组。
    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    // Compose a CGRect from the separate AX position and size attributes.
    // 从 AX 分开的坐标和尺寸属性组合出 CGRect。
    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    // AXValue is dynamically typed, so verify it contains a CGPoint before extracting.
    // AXValue 是动态类型，提取前需确认其中包含 CGPoint。
    private func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgPoint
        else {
            return nil
        }

        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    // AXValue is dynamically typed, so verify it contains a CGSize before extracting.
    // AXValue 是动态类型，提取前需确认其中包含 CGSize。
    private func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgSize
        else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}
