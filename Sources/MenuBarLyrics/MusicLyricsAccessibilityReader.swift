import ApplicationServices
import AppKit
import Foundation

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

final class MusicLyricsAccessibilityReader: @unchecked Sendable {
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

    var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermissionIfNeeded() {
        guard !isPermissionGranted else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

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

    private func windows(in appElement: AXUIElement) -> [AXUIElement] {
        if let windows = elementArrayAttribute(kAXWindowsAttribute, from: appElement), !windows.isEmpty {
            return windows
        }

        return [appElement]
    }

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

    private func lyricPanelSort(_ lhs: TextCandidate, _ rhs: TextCandidate) -> Bool {
        let lhsMinY = lhs.frame?.minY ?? .greatestFiniteMagnitude
        let rhsMinY = rhs.frame?.minY ?? .greatestFiniteMagnitude
        if lhsMinY != rhsMinY {
            return lhsMinY < rhsMinY
        }

        return lhs.text.count > rhs.text.count
    }

    private func isBetterCandidate(_ lhs: TextCandidate, _ rhs: TextCandidate) -> Bool {
        let lhsScore = candidateScore(lhs)
        let rhsScore = candidateScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        return lyricPanelSort(lhs, rhs)
    }

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

    private func isTimeLikeText(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else {
            return false
        }

        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    private func isOnlyPunctuation(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    private func isTrackMetadata(_ text: String, nowPlaying: NowPlaying) -> Bool {
        let normalizedText = normalized(text)
        let metadata = [
            nowPlaying.title,
            nowPlaying.artist,
            nowPlaying.album
        ].map(normalized)

        return metadata.contains(normalizedText)
    }

    private func isLyricsPanelLabel(_ text: String) -> Bool {
        ["歌词", "Lyrics"].map(normalized).contains(normalized(text))
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

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
